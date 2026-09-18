package com.budgett.budgett_frontend.capture

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Takes a location fix at the moment a bank message arrives.
 *
 * Uses the platform [LocationManager] directly rather than Play Services so the
 * APK gains no extra dependency — this runs from a notification listener and an
 * SMS receiver, both of which need the fix to be cheap and self-contained.
 *
 * On Android 10+ this only returns anything when ACCESS_BACKGROUND_LOCATION has
 * been granted, because both callers are background components. Everything here
 * degrades to null rather than throwing: a missing fix must never cost us the
 * expense itself.
 */
object LocationSnapshot {

    private const val TAG = "BudgettCapture"

    /** A cached fix this fresh is good enough — no need to wake the GPS. */
    private const val FRESH_ENOUGH_MS = 90_000L

    /** Above this radius a cached fix is too vague to name a place. */
    private const val USABLE_ACCURACY_M = 250f

    data class Fix(val latitude: Double, val longitude: Double, val accuracy: Double?)

    fun hasPermission(context: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) return false

        // A background component needs the background grant from Android 10 on.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    /**
     * Blocks for at most [timeoutMs] trying to get a usable fix. Call from a
     * worker thread — never from a service callback.
     */
    @SuppressLint("MissingPermission") // guarded by hasPermission() above
    fun acquire(context: Context, timeoutMs: Long = 8_000L): Fix? {
        if (!CaptureStore.isLocationEnabled(context)) return null
        if (!hasPermission(context)) return null

        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null

        val cached = bestLastKnown(manager)
        if (cached != null && isFreshAndPrecise(cached)) return cached.toFix()

        val live = requestSingleFix(manager, timeoutMs)
        return (live ?: cached)?.toFix()
    }

    private fun Location.toFix() = Fix(
        latitude = latitude,
        longitude = longitude,
        accuracy = if (hasAccuracy()) accuracy.toDouble() else null,
    )

    private fun isFreshAndPrecise(location: Location): Boolean {
        val age = System.currentTimeMillis() - location.time
        val precise = !location.hasAccuracy() || location.accuracy <= USABLE_ACCURACY_M
        return age in 0..FRESH_ENOUGH_MS && precise
    }

    /** Freshest cached fix across every enabled provider. */
    @SuppressLint("MissingPermission") // callers check hasPermission() first
    private fun bestLastKnown(manager: LocationManager): Location? {
        var best: Location? = null
        for (provider in safeProviders(manager)) {
            val candidate = try {
                manager.getLastKnownLocation(provider)
            } catch (e: SecurityException) {
                null
            } catch (e: Exception) {
                null
            } ?: continue
            if (best == null || candidate.time > best!!.time) best = candidate
        }
        return best
    }

    private fun safeProviders(manager: LocationManager): List<String> = try {
        manager.getProviders(true)
    } catch (e: Exception) {
        emptyList()
    }

    @SuppressLint("MissingPermission") // callers check hasPermission() first
    private fun requestSingleFix(
        manager: LocationManager,
        timeoutMs: Long,
    ): Location? {
        val provider = pickProvider(manager) ?: return null

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                currentLocationApi30(manager, provider, timeoutMs)
            } else {
                singleUpdateLegacy(manager, provider, timeoutMs)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Location permission revoked mid-request", e)
            null
        } catch (e: Exception) {
            Log.w(TAG, "Location fix failed", e)
            null
        }
    }

    /** Prefers the fused provider, then GPS, then network. */
    private fun pickProvider(manager: LocationManager): String? {
        val enabled = safeProviders(manager)
        val preferred = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(LocationManager.FUSED_PROVIDER)
            }
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
        }
        return preferred.firstOrNull { enabled.contains(it) } ?: enabled.firstOrNull()
    }

    @SuppressLint("MissingPermission") // callers check hasPermission() first
    private fun currentLocationApi30(
        manager: LocationManager,
        provider: String,
        timeoutMs: Long,
    ): Location? {
        val latch = CountDownLatch(1)
        var result: Location? = null
        val cancellation = CancellationSignal()

        manager.getCurrentLocation(
            provider,
            cancellation,
            { runnable -> runnable.run() },
        ) { location ->
            result = location
            latch.countDown()
        }

        if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) {
            cancellation.cancel()
        }
        return result
    }

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission") // callers check hasPermission() first
    private fun singleUpdateLegacy(
        manager: LocationManager,
        provider: String,
        timeoutMs: Long,
    ): Location? {
        val latch = CountDownLatch(1)
        var result: Location? = null

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                result = location
                latch.countDown()
            }

            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                latch.countDown()
            }

            @Deprecated("Required by the pre-API-30 LocationListener contract")
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
        }

        manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } finally {
            try {
                manager.removeUpdates(listener)
            } catch (e: Exception) {
                // Already removed.
            }
        }
        return result
    }
}
