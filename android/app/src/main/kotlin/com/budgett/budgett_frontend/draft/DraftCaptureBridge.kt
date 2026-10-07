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

        /**
         * Failures that mean "not with this language, like this" rather than
         * "not at all", so they are worth one retry online with a broader
         * tag. 11 is SERVER_DISCONNECTED, 12 LANGUAGE_NOT_SUPPORTED, 13
         * LANGUAGE_UNAVAILABLE — numeric because the constants arrived in
         * API 33 and this project builds against an older minSdk.
         */
        private val LANGUAGE_ERRORS = setOf(
            11, 12, 13,
            SpeechRecognizer.ERROR_NETWORK,
        )

        /**
         * Failures that mean the recogniser stopped before the speaker did.
         * If a partial transcription survives, it is worth more than the
         * error: half a sentence still usually carries the amount.
         */
        private val CUT_SHORT_ERRORS = setOf(
            SpeechRecognizer.ERROR_NO_MATCH,
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
        )
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
                .addOnSuccessListener { text -> result.success(inReadingOrder(text)) }
                .addOnFailureListener { error ->
                    result.error("ocr_failed", error.message, null)
                }
        } catch (e: Exception) {
            result.error("ocr_failed", e.message, null)
        }
    }

    /**
     * Rebuilds reading order from where the text sits on screen.
     *
     * ML Kit groups text into BLOCKS, and a bank app's movements list is two
     * columns: descriptions down the left, amounts right-aligned. Those are
     * different blocks, so walking blocks in order returns every description
     * first and every amount afterwards. Dart then sees rows with no amount
     * and a pile of orphan figures, which is exactly what happened to a real
     * screenshot: three movements came back as two, one of them "cut off"
     * with its amount plainly on screen and another carrying a number from
     * the status bar.
     *
     * So the lines are sorted by where they are, not by how they were
     * grouped, and lines sharing a row are joined left to right — which is
     * also what puts "PAGO QR MOTOS GP ITAG" and "-$ 557.000,00" back on one
     * line when the app draws them side by side.
     */
    private fun inReadingOrder(text: com.google.mlkit.vision.text.Text): String {
        data class Fragment(val text: String, val top: Int, val left: Int, val height: Int)

        val fragments = text.textBlocks
            .flatMap { it.lines }
            .mapNotNull { line ->
                val box = line.boundingBox ?: return@mapNotNull null
                val content = line.text.trim()
                if (content.isEmpty()) null
                else Fragment(content, box.top, box.left, box.height())
            }
            .sortedWith(compareBy({ it.top }, { it.left }))

        if (fragments.isEmpty()) {
            // No bounding boxes at all (it can happen): fall back to the
            // flat reading rather than returning nothing.
            return text.text.trim()
        }

        // Two fragments belong to the same row when their tops are closer
        // than half a line height. A fixed pixel tolerance would be wrong
        // across a 1080p screenshot and a 12-megapixel photo.
        val rows = mutableListOf<MutableList<Fragment>>()
        for (fragment in fragments) {
            val tolerance = (fragment.height / 2).coerceAtLeast(6)
            val row = rows.lastOrNull()
            val anchor = row?.firstOrNull()
            if (row != null && anchor != null &&
                kotlin.math.abs(fragment.top - anchor.top) <= tolerance
            ) {
                row.add(fragment)
            } else {
                rows.add(mutableListOf(fragment))
            }
        }

        return rows.joinToString("\n") { row ->
            row.sortedBy { it.left }.joinToString(" ") { it.text }
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

        // Spanish first and offline first, then progressively less fussy.
        //
        // The on-device recogniser only has the language packs the phone has
        // downloaded, and this phone is set to English, so asking for es-CO
        // offline failed outright. Falling back through the broader tag, then
        // online, then whatever the device itself is set to, means dictation
        // works today and gets better the moment a Spanish pack is installed
        // — and the parser reads English anyway.
        val attempts = buildList {
            add(locale to true)
            val broad = broaden(locale)
            if (broad != locale) add(broad to true)
            add(broad to false)
            val device = Locale.getDefault().toLanguageTag()
            if (broaden(device) != broad) add(device to false)
        }
        listen(attempts, 0)
    }

    /**
     * Runs [attempts] in order until one is heard.
     *
     * Each is a language tag and whether to insist the audio stays on the
     * phone. Only a language or availability failure moves to the next one:
     * "nothing was heard" is an answer, and retrying it would make the user
     * wait three times over for the same silence.
     */
    private fun listen(attempts: List<Pair<String, Boolean>>, index: Int) {
        val (locale, offline) = attempts[index]
        main.post {
            stopRecognizer()
            val recognizer = SpeechRecognizer.createSpeechRecognizer(context)
            speechRecognizer = recognizer

            // The best transcription seen so far. A pause mid-sentence makes
            // the recogniser give up with ERROR_NO_MATCH, and without this
            // everything already said went with it.
            var heardSoFar = ""

            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                    finish { it.success(if (text.isNotBlank()) text else heardSoFar) }
                }

                override fun onError(error: Int) {
                    if (error in LANGUAGE_ERRORS && index + 1 < attempts.size) {
                        stopRecognizer()
                        listen(attempts, index + 1)
                        return
                    }
                    // Cut short, but something was understood. Handing back
                    // half a sentence beats handing back "nothing was heard"
                    // and losing the amount with it.
                    if (error in CUT_SHORT_ERRORS && heardSoFar.isNotBlank()) {
                        finish { it.success(heardSoFar) }
                        return
                    }
                    finish { it.error("speech_error", describe(error), null) }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                    // Longest wins: a later partial is sometimes a re-guess of
                    // the last word rather than the whole utterance.
                    if (partial.length > heardSoFar.length) heardSoFar = partial
                }

                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
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
                // Partials are what make a cut-off recoverable.
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)

                // Android stops listening after about a second of silence,
                // which means dictating an expense has to be done in one
                // breath. Someone saying "Mariana me envió un pago… de un
                // préstamo" pauses in the middle and loses the rest.
                //
                // These are a request, not a guarantee — the recogniser may
                // ignore them — which is why the partial-result fallback
                // above exists as well.
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                    3000L,
                )
                putExtra(
                    RecognizerIntent
                        .EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    3000L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                    4000L,
                )

                if (offline) {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
            }
            recognizer.startListening(intent)
        }
    }

    /** "es-CO" becomes "es": the region is what the device usually lacks. */
    private fun broaden(locale: String): String =
        locale.substringBefore('-').substringBefore('_')

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
        // Numeric rather than by constant: these arrived in API 33 and this
        // project compiles against an older minSdk, where the symbols do not
        // exist. A bare "code 12" is what sent the first real attempt back
        // with nothing to act on.
        10 -> "Too many requests just now — try again in a moment"
        11 -> "The speech service disconnected"
        12, 13 -> "Spanish speech recognition is not installed on this phone. " +
            "Add it in Settings › General management › Voice input."
        14 -> "Could not check which languages are available"
        15 -> "Could not follow the language download"
        else -> "Speech recognition failed (code $error)"
    }

}
