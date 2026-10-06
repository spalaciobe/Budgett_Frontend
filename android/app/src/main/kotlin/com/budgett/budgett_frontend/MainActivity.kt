package com.budgett.budgett_frontend

import com.budgett.budgett_frontend.capture.MessageCaptureBridge
import com.budgett.budgett_frontend.draft.DraftCaptureBridge
import com.budgett.budgett_frontend.draft.LocalLlmBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var captureBridge: MessageCaptureBridge? = null
    private var draftBridge: DraftCaptureBridge? = null
    private var llmBridge: LocalLlmBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = MessageCaptureBridge(applicationContext)
        bridge.activity = this
        captureBridge = bridge

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MessageCaptureBridge.CHANNEL,
        ).setMethodCallHandler(bridge)

        // Receipt OCR and dictation, for expenses entered by camera or voice.
        val draft = DraftCaptureBridge(applicationContext)
        draft.activity = this
        draftBridge = draft
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DraftCaptureBridge.CHANNEL,
        ).setMethodCallHandler(draft)

        // The optional local model. Constructing this loads nothing: the
        // weights are only touched when a generation is actually asked for.
        val llm = LocalLlmBridge(applicationContext)
        llmBridge = llm
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LocalLlmBridge.CHANNEL,
        ).setMethodCallHandler(llm)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // The capture bridge requests SMS and location itself; it returns true
        // when the code was its own, so plugins still see everything else.
        val handled = captureBridge
            ?.onRequestPermissionsResult(requestCode, permissions, grantResults)
            ?: false
        val handledByDraft = !handled && (draftBridge
            ?.onRequestPermissionsResult(requestCode, permissions, grantResults)
            ?: false)
        if (!handled && !handledByDraft) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        captureBridge?.activity = null
        captureBridge = null
        draftBridge?.activity = null
        draftBridge?.dispose()
        draftBridge = null
        llmBridge?.dispose()
        llmBridge = null
        super.onDestroy()
    }
}
