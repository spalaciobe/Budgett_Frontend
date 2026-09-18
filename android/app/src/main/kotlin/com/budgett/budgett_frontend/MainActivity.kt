package com.budgett.budgett_frontend

import com.budgett.budgett_frontend.capture.MessageCaptureBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var captureBridge: MessageCaptureBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = MessageCaptureBridge(applicationContext)
        bridge.activity = this
        captureBridge = bridge

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MessageCaptureBridge.CHANNEL,
        ).setMethodCallHandler(bridge)
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
        if (!handled) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun onDestroy() {
        captureBridge?.activity = null
        captureBridge = null
        super.onDestroy()
    }
}
