package com.budgett.budgett_frontend.capture

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel between Flutter and the capture components.
 *
 * Flutter owns the policy (what counts as an expense, which account, which
 * category); this side reports and requests permissions, stores the
 * configuration the native components read, and hands over the queued messages.
 *
 * Permissions are handled here rather than through a plugin because the status
 * checks already had to live natively — the notification listener and the SMS
 * receiver run with no Flutter engine attached — so requesting belongs in the
 * same place.
 */
class MessageCaptureBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "budgett/message_capture"

        private const val REQ_SMS = 9101
        private const val REQ_LOCATION = 9102
        private const val REQ_BACKGROUND_LOCATION = 9103
    }

    /** Set while an Activity is attached; required to show permission dialogs. */
    var activity: Activity? = null

    private var pendingResult: MethodChannel.Result? = null
    private var pendingRequestCode: Int = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(buildStatus())

            "applyConfig" -> {
                val config = call.arguments as? Map<*, *>
                if (config == null) {
                    result.error("bad_args", "applyConfig expects a map", null)
                    return
                }
                CaptureStore.applyConfig(context, config)
                result.success(buildStatus())
            }

            "openNotificationAccessSettings" ->
                result.success(openNotificationAccessSettings())

            "openAppSettings" -> result.success(openAppSettings())

            "requestSmsPermission" ->
                request(result, REQ_SMS, arrayOf(Manifest.permission.RECEIVE_SMS))

            "requestLocationPermission" -> request(
                result,
                REQ_LOCATION,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )

            "requestBackgroundLocation" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    // No separate background grant before Android 10.
                    result.success(hasPermission(Manifest.permission.ACCESS_FINE_LOCATION))
                } else {
                    request(
                        result,
                        REQ_BACKGROUND_LOCATION,
                        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                    )
                }
            }

            "drain" -> result.success(CaptureStore.drain(context))

            "queuedCount" -> result.success(CaptureStore.queuedCount(context))

            "clearQueue" -> {
                CaptureStore.clear(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ─── permissions ─────────────────────────────────────────────────────────

    private fun request(
        result: MethodChannel.Result,
        requestCode: Int,
        permissions: Array<String>,
    ) {
        if (permissions.all { hasPermission(it) }) {
            result.success(true)
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no_activity", "No attached activity to request from", null)
            return
        }
        if (pendingResult != null) {
            result.error("in_progress", "A permission request is already open", null)
            return
        }

        pendingResult = result
        pendingRequestCode = requestCode
        ActivityCompat.requestPermissions(currentActivity, permissions, requestCode)
    }

    /**
     * Completes the pending request. Returns true when this bridge owned the
     * request code, so the Activity knows whether it handled the callback.
     */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != pendingRequestCode) return false
        val result = pendingResult ?: return false

        pendingResult = null
        pendingRequestCode = 0

        // ACCESS_BACKGROUND_LOCATION cannot be granted from a dialog on
        // Android 11+ — the user has to pick "Allow all the time" in app
        // settings — so an empty or denied result is expected there, and the
        // Flutter side offers that next step.
        val granted = grantResults.isNotEmpty() &&
            grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        result.success(granted)
        return true
    }

    private fun buildStatus(): Map<String, Any?> = mapOf(
        "enabled" to CaptureStore.isEnabled(context),
        "smsEnabled" to CaptureStore.isSmsEnabled(context),
        "locationEnabled" to CaptureStore.isLocationEnabled(context),
        "notificationAccess" to hasNotificationAccess(),
        "smsPermission" to hasPermission(Manifest.permission.RECEIVE_SMS),
        "locationPermission" to hasPermission(Manifest.permission.ACCESS_FINE_LOCATION),
        "backgroundLocationPermission" to hasBackgroundLocation(),
        "queued" to CaptureStore.queuedCount(context),
    )

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasBackgroundLocation(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return hasPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
    }

    /**
     * Notification access is a special grant with no runtime dialog — the user
     * has to flip it in system settings, so all we can do is read it.
     */
    private fun hasNotificationAccess(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context)
            .contains(context.packageName)

    private fun openNotificationAccessSettings(): Boolean {
        // Android 11+ can deep-link straight to this app's row; older versions
        // only accept the plain settings screen.
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                add(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).apply {
                        putExtra(
                            Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                            ComponentName(
                                context,
                                NotificationCaptureService::class.java,
                            ).flattenToString(),
                        )
                    }
                )
            }
            add(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }

        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try the next, less specific, intent.
            }
        }
        return false
    }

    private fun openAppSettings(): Boolean = try {
        context.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        false
    }
}
