package com.budgett.budgett_frontend.draft

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Reads a receipt photo or a spoken phrase into text, on the device.
 *
 * Both jobs are native for the same reason the message-capture permissions
 * are: the Android APIs are already here, and adding a Flutter plugin for
 * either would drag in a newer Kotlin Gradle plugin than this project builds
 * with.
 *
 * Everything returns TEXT. Turning text into an expense is Dart's job
 * (`receipt_parser.dart`, `voice_expense_parser.dart`), so the reading and
 * the understanding stay testable apart from each other.
 */
class DraftCaptureBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "budgett/draft_capture"
        private const val SPEECH_PERMISSION_REQUEST = 7311
    }

    var activity: Activity? = null

    private val main = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null

    /** Set while a dictation is in flight, so a second start cannot strand it. */
    private var pendingSpeech: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizeText" -> recognizeText(call.argument<String>("path"), result)
            "speechAvailable" -> result.success(
                SpeechRecognizer.isRecognitionAvailable(context) && hasMicPermission()
            )
            "requestMicPermission" -> requestMicPermission(result)
            "startDictation" -> startDictation(
                call.argument<String>("locale") ?: "es-CO", result
            )
            "cancelDictation" -> {
                stopRecognizer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Receipts ─────────────────────────────────────────────────────────

    /**
     * OCR on a photo already written to disk by the image picker.
     *
     * Returns the lines in reading order joined by newlines, which is what
     * `parseReceipt` expects: it reads the total by its LABEL, so losing the
     * line structure would lose the only thing that tells a total from a
     * subtotal.
     */
    private fun recognizeText(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("no_path", "No image path given", null)
            return
        }
        try {
            val image = InputImage.fromFilePath(context, Uri.parse("file://$path"))
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                .process(image)
                .addOnSuccessListener { text ->
                    // `text.text` already joins blocks with newlines, but
                    // going through the blocks keeps the order explicit and
                    // drops the empties a blurry photo produces.
                    val lines = text.textBlocks
                        .flatMap { block -> block.lines }
                        .map { it.text.trim() }
                        .filter { it.isNotEmpty() }
                    result.success(lines.joinToString("\n"))
                }
                .addOnFailureListener { error ->
                    result.error("ocr_failed", error.message, null)
                }
        } catch (e: Exception) {
            result.error("ocr_failed", e.message, null)
        }
    }

    // ── Dictation ────────────────────────────────────────────────────────

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

    private fun requestMicPermission(result: MethodChannel.Result) {
        if (hasMicPermission()) {
            result.success(true)
            return
        }
        val current = activity
        if (current == null) {
            result.success(false)
            return
        }
        pendingPermission = result
        current.requestPermissions(
            arrayOf(android.Manifest.permission.RECORD_AUDIO),
            SPEECH_PERMISSION_REQUEST,
        )
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != SPEECH_PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    /**
     * One phrase, transcribed on the device.
     *
     * `EXTRA_PREFER_OFFLINE` keeps the audio on the phone. On a device with
     * no offline model for the language Android falls back to its own
     * service; the recogniser decides, and there is no way to force it
     * without failing outright, which would be worse than transcribing.
     */
    private fun startDictation(locale: String, result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            result.error("unavailable", "Speech recognition is not available", null)
            return
        }
        if (!hasMicPermission()) {
            result.error("no_permission", "Microphone permission not granted", null)
            return
        }

        // A dictation already running is abandoned rather than queued: the
        // user pressed the button again, so the older one is not wanted.
        pendingSpeech?.error("cancelled", "Replaced by a new dictation", null)
        pendingSpeech = result

        main.post {
            stopRecognizer()
            val recognizer = SpeechRecognizer.createSpeechRecognizer(context)
            speechRecognizer = recognizer

            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                    finish { it.success(text) }
                }

                override fun onError(error: Int) {
                    finish { it.error("speech_error", describe(error), null) }
                }

                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
            })

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            recognizer.startListening(intent)
        }
    }

    /** Answers the pending call exactly once and tears the recogniser down. */
    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        val pending = pendingSpeech
        pendingSpeech = null
        stopRecognizer()
        if (pending != null) reply(pending)
    }

    private fun stopRecognizer() {
        speechRecognizer?.let {
            it.cancel()
            it.destroy()
        }
        speechRecognizer = null
    }

    fun dispose() {
        pendingSpeech?.error("cancelled", "Screen closed", null)
        pendingSpeech = null
        pendingPermission = null
        stopRecognizer()
    }

    private fun describe(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "Could not record audio"
        SpeechRecognizer.ERROR_CLIENT -> "The recogniser stopped unexpectedly"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission denied"
        SpeechRecognizer.ERROR_NETWORK -> "No network, and no offline model for this language"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "The recogniser timed out"
        SpeechRecognizer.ERROR_NO_MATCH -> "Nothing was heard"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The recogniser is busy"
        SpeechRecognizer.ERROR_SERVER -> "The speech service failed"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected"
        else -> "Speech recognition failed (code $error)"
    }

    @Suppress("unused")
    private fun defaultLocale(): String = Locale.getDefault().toLanguageTag()
}
