package com.budgett.budgett_frontend.widget

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Lets Flutter hand the widget a new schedule, or take it away on sign-out. */
class CardWidgetBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "budgett/card_widget"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                val json = call.arguments as? String
                if (json == null) {
                    result.error("bad_args", "update expects a JSON string", null)
                    return
                }
                CardWidgetStore.save(context, json)
                BestCardWidgetProvider.refreshAll(context)
                result.success(null)
            }

            "clear" -> {
                CardWidgetStore.clear(context)
                BestCardWidgetProvider.refreshAll(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
