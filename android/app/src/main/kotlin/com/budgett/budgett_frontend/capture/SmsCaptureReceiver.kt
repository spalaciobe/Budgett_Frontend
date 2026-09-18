package com.budgett.budgett_frontend.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Captures bank SMS alerts. The second source that makes deduplication
 * necessary: most Colombian issuers send both a push notification and an SMS
 * for the same purchase, seconds apart.
 *
 * Multipart messages arrive as several PDUs in one broadcast, so the parts are
 * regrouped by sender before anything is queued — otherwise a long alert would
 * be captured as two half-messages, neither of which parses.
 */
class SmsCaptureReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BudgettCapture"
        private val worker = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        val appContext = context?.applicationContext ?: return
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!CaptureStore.isEnabled(appContext)) return
        if (!CaptureStore.isSmsEnabled(appContext)) return

        val messages = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read SMS from intent", e)
            return
        } ?: return

        // Regroup multipart messages: same sender, concatenated in order.
        val bodies = LinkedHashMap<String, StringBuilder>()
        val timestamps = LinkedHashMap<String, Long>()
        for (message in messages) {
            val sender = message?.originatingAddress ?: continue
            bodies.getOrPut(sender) { StringBuilder() }.append(message.messageBody ?: "")
            timestamps.putIfAbsent(sender, message.timestampMillis)
        }

        val blocked = CaptureStore.blockedSources(appContext)
        val allowed = CaptureStore.allowedSources(appContext)

        val pending = bodies.entries.mapNotNull { (sender, builder) ->
            val body = builder.toString()
            val shouldCapture = FinancialTextFilter.shouldCapture(
                text = body,
                sourceKey = sender,
                enabled = true,
                blocked = blocked,
                allowed = allowed,
            )
            if (!shouldCapture) null else Triple(
                sender,
                body,
                timestamps[sender]?.takeIf { it > 0 } ?: System.currentTimeMillis(),
            )
        }

        if (pending.isEmpty()) return

        // One fix for the whole broadcast — these messages arrived together.
        worker.execute {
            try {
                val fix = LocationSnapshot.acquire(appContext)
                for ((sender, body, receivedAt) in pending) {
                    val record = JSONObject().apply {
                        put("channel", "sms")
                        put("sourceKey", sender)
                        put("sourceName", sender)
                        put("title", JSONObject.NULL)
                        put("body", body)
                        put("receivedAt", receivedAt)
                        if (fix != null) {
                            put("latitude", fix.latitude)
                            put("longitude", fix.longitude)
                            fix.accuracy?.let { put("locationAccuracy", it) }
                        }
                    }
                    CaptureStore.enqueue(appContext, record)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to capture SMS", e)
            }
        }
    }
}
