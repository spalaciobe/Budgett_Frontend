package com.budgett.budgett_frontend.capture

import android.app.Notification
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Captures bank notifications while the app is closed.
 *
 * Requires the user to grant "notification access" in system settings — there
 * is no runtime dialog for it, so the settings screen deep-links there.
 *
 * The callback itself does almost nothing: it reads the notification's text and
 * hands it to a worker thread, because acquiring a location fix can take
 * several seconds and blocking this callback would stall the whole system
 * notification pipeline.
 */
class NotificationCaptureService : NotificationListenerService() {

    companion object {
        private const val TAG = "BudgettCapture"
    }

    private val worker = Executors.newSingleThreadExecutor()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        val packageName = sbn.packageName ?: return

        // Never capture our own notifications — that would feed the pipeline
        // its own output.
        if (packageName == applicationContext.packageName) return

        // Group summaries repeat their children's text, and ongoing
        // notifications (media players, downloads) are not events.
        if (isGroupSummary(notification)) return
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = listOfNotNull(
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
        ).maxByOrNull { it.length }.orEmpty()

        if (title.isBlank() && body.isBlank()) return

        val enabled = CaptureStore.isEnabled(applicationContext)
        val blocked = CaptureStore.blockedSources(applicationContext)
        val allowed = CaptureStore.allowedSources(applicationContext)

        if (!FinancialTextFilter.shouldCapture(
                text = "$title $body",
                sourceKey = packageName,
                enabled = enabled,
                blocked = blocked,
                allowed = allowed,
            )
        ) {
            return
        }

        val postedAt = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis()
        val appLabel = resolveAppLabel(packageName)

        worker.execute {
            try {
                val fix = LocationSnapshot.acquire(applicationContext)
                val record = JSONObject().apply {
                    put("channel", "notification")
                    put("sourceKey", packageName)
                    put("sourceName", appLabel)
                    put("title", title)
                    put("body", body)
                    put("receivedAt", postedAt)
                    if (fix != null) {
                        put("latitude", fix.latitude)
                        put("longitude", fix.longitude)
                        fix.accuracy?.let { put("locationAccuracy", it) }
                    }
                }
                CaptureStore.enqueue(applicationContext, record)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to capture notification from $packageName", e)
            }
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    private fun isGroupSummary(notification: Notification): Boolean =
        notification.flags and Notification.FLAG_GROUP_SUMMARY != 0

    private fun resolveAppLabel(packageName: String): String? = try {
        val pm = applicationContext.packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getApplicationInfo(
                packageName,
                PackageManager.ApplicationInfoFlags.of(0L),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getApplicationInfo(packageName, 0)
        }
        pm.getApplicationLabel(info).toString()
    } catch (e: Exception) {
        null
    }
}
