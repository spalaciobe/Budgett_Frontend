package com.budgett.budgett_frontend.draft

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The optional on-device model, used only for what the rules cannot read.
 *
 * It is a backup, not the engine. `receipt_parser.dart` and
 * `voice_expense_parser.dart` run first and are right most of the time; this
 * is for the blurry receipt and the half-heard sentence, where the choice is
 * between a model's guess and an empty form.
 *
 * Nothing here is bundled. The weights are gigabytes and this app updates
 * itself over the air, so the model is downloaded once, deliberately, into
 * app storage, and everything degrades to "not installed" until it is. That
 * is also why every method answers rather than throwing: the feature has to
 * work on a phone that never downloads it.
 */
class LocalLlmBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "budgett/local_llm"

        /** Where a downloaded model lives. One file, replaced in place. */
        private const val MODEL_FILE = "local_model.task"

        /**
         * The whole context window — prompt AND answer — not a cap on the
         * answer alone. That distinction matters: the extraction prompt is
         * about 250 tokens before the receipt text is appended, so the 256
         * this used to be left the model no room to reply at all.
         *
         * A thousand covers the prompt, a screenshot's worth of OCR, and the
         * line of JSON wanted back, without reserving memory for a
         * conversation this never has.
         */
        private const val MAX_TOKENS = 1024
    }

    /**
     * Inference runs off the main thread: even a 2B model takes seconds on a
     * phone, and a single thread keeps two requests from loading the weights
     * twice.
     */
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Loaded lazily and kept, because loading is the expensive part. */
    @Volatile
    private var engine: LlmInference? = null

    private fun modelFile(): File = File(context.filesDir, MODEL_FILE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isInstalled" -> result.success(modelFile().isFile && modelFile().length() > 0)

            "modelPath" -> result.success(modelFile().absolutePath)

            "sizeBytes" -> result.success(
                if (modelFile().isFile) modelFile().length() else 0L
            )

            "remove" -> {
                closeEngine()
                result.success(modelFile().delete())
            }

            "generate" -> generate(
                prompt = call.argument<String>("prompt").orEmpty(),
                result = result,
            )

            "unload" -> {
                closeEngine()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun generate(prompt: String, result: MethodChannel.Result) {
        val file = modelFile()
        if (!file.isFile || file.length() == 0L) {
            result.error("not_installed", "No local model is installed", null)
            return
        }
        if (prompt.isBlank()) {
            result.error("empty_prompt", "No prompt given", null)
            return
        }

        worker.execute {
            try {
                val llm = engine ?: LlmInference.createFromOptions(
                    context,
                    LlmInference.LlmInferenceOptions.builder()
                        .setModelPath(file.absolutePath)
                        .setMaxTokens(MAX_TOKENS)
                        .build(),
                ).also { engine = it }

                val answer = llm.generateResponse(prompt)
                main.post { result.success(answer) }
            } catch (e: Throwable) {
                // Throwable, not Exception: a model file that does not match
                // the runtime fails with an UnsatisfiedLinkError, and that
                // has to surface as "this model does not work here" rather
                // than taking the process down.
                closeEngine()
                main.post {
                    result.error("inference_failed", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun closeEngine() {
        try {
            engine?.close()
        } catch (_: Throwable) {
            // Closing a half-initialised engine is not worth reporting.
        }
        engine = null
    }

    fun dispose() {
        closeEngine()
        worker.shutdown()
    }
}
