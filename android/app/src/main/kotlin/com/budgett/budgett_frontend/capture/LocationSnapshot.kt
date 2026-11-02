package com.budgett.budgett_frontend.capture

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationRequest
import android.os.Build
import android.os.CancellationSignal
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
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

    /**
     * Radius a cached fix needs to skip the live request. 250 m let a wifi or
     * cell estimate through, and in a dense neighbourhood that is several
     * blocks — a different street from the shop.
     */
    private const val PRECISE_ACCURACY_M = 50f

    /**
     * Oldest cached fix worth keeping as a fallback. Past this it is where the
     * user was earlier, not where they paid — no location beats a wrong one.
     */
    private const val STALE_AFTER_MS = 5 * 60_000L

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
        // The live fix is not automatically better: when GPS cannot lock in
        // time the platform hands back a coarse network estimate, and a GPS
        // fix from two minutes ago is closer to the till than that.
        return listOfNotNull(live, cached).minByOrNull { it.radius() }?.toFix()
    }

    /** Accuracy radius, with an unknown one ranked last. */
    private fun Location.radius(): Float =
        if (hasAccuracy()) accuracy else Float.MAX_VALUE

    private fun Location.ageMs(): Long = System.currentTimeMillis() - time

    private fun Location.toFix() = Fix(
        latitude = latitude,
        longitude = longitude,
        accuracy = if (hasAccuracy()) accuracy.toDouble() else null,
    )

    private fun isFreshAndPrecise(location: Location): Boolean =
        location.ageMs() in 0..FRESH_ENOUGH_MS &&
            location.hasAccuracy() && location.accuracy <= PRECISE_ACCURACY_M

    /**
     * Most precise recent cached fix across every enabled provider.
     *
     * Ranked by accuracy, not recency: picking the newest let a cell-tower
     * estimate a kilometre wide beat a GPS fix taken seconds earlier.
     */
    @SuppressLint("MissingPermission") // callers check hasPermission() first
    private fun bestLastKnown(manager: LocationManager): Location? {
        return safeProviders(manager)
            .mapNotNull { provider ->
                try {
                    manager.getLastKnownLocation(provider)
                } catch (e: Exception) {
                    null
                }
            }
            .filter { it.ageMs() in 0..STALE_AFTER_MS }
            .minByOrNull { it.radius() }
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                currentLocationApi31(manager, provider, timeoutMs)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
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

    /**
     * Asks for high accuracy explicitly. Without a [LocationRequest] the fused
     * provider answers at balanced-power quality — wifi and cell towers, often
     * a hundred metres or more out — which is how payments were being placed
     * a few streets away from the shop.
     */
    @RequiresApi(Build.VERSION_CODES.S)
    @SuppressLint("MissingPermission") // callers check hasPermission() first
    private fun currentLocationApi31(
        manager: LocationManager,
        provider: String,
        timeoutMs: Long,
    ): Location? {
        val latch = CountDownLatch(1)
        var result: Location? = null
        val cancellation = CancellationSignal()
        val request = LocationRequest.Builder(0L)
            .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
            .setDurationMillis(timeoutMs)
            .build()

        manager.getCurrentLocation(
            provider,
            request,
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
