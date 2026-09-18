package com.budgett.budgett_frontend.capture

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Append-only queue of captured messages, plus the native side of the capture
 * configuration.
 *
 * Why a file and not a direct upload: the notification listener and the SMS
 * receiver run with no Flutter engine attached and no Supabase session, so they
 * cannot post anything themselves. They append here; Flutter drains the queue
 * the next time the app reaches the foreground and does the parsing, dedup and
 * insertion where the session and the user's rules live.
 *
 * Configuration lives in its own SharedPreferences file rather than in the one
 * `shared_preferences` owns, so a plugin storage change cannot silently turn
 * capture off.
 */
object CaptureStore {

    private const val TAG = "BudgettCapture"
    private const val QUEUE_FILE = "budgett_captures.jsonl"
    private const val PREFS = "budgett_capture_prefs"

    private const val KEY_ENABLED = "capture_enabled"
    private const val KEY_LOCATION_ENABLED = "location_enabled"
    private const val KEY_SMS_ENABLED = "sms_enabled"
    private const val KEY_BLOCKED = "blocked_sources"
    private const val KEY_ALLOWED = "allowed_sources"

    /** Hard cap so a runaway notification source cannot fill the disk. */
    private const val MAX_RECORDS = 500

    private val lock = Any()

    // ─── configuration ───────────────────────────────────────────────────────

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun isLocationEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_LOCATION_ENABLED, true)

    fun isSmsEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SMS_ENABLED, true)

    /**
     * Sources the user switched off. A blocked source is dropped before its
     * text is ever looked at, let alone written to disk.
     */
    fun blockedSources(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()

    /**
     * When non-empty, ONLY these sources are captured and the
     * "does it look financial" heuristic is skipped for them. Empty means
     * discovery mode: any source is allowed, but only messages that look like
     * a bank alert are kept.
     */
    fun allowedSources(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet()

    fun applyConfig(context: Context, config: Map<*, *>) {
        val editor = prefs(context).edit()
        (config["enabled"] as? Boolean)?.let { editor.putBoolean(KEY_ENABLED, it) }
        (config["locationEnabled"] as? Boolean)?.let {
            editor.putBoolean(KEY_LOCATION_ENABLED, it)
        }
        (config["smsEnabled"] as? Boolean)?.let {
            editor.putBoolean(KEY_SMS_ENABLED, it)
        }
        (config["blockedSources"] as? List<*>)?.let { list ->
            editor.putStringSet(KEY_BLOCKED, list.mapNotNull { it as? String }.toSet())
        }
        (config["allowedSources"] as? List<*>)?.let { list ->
            editor.putStringSet(KEY_ALLOWED, list.mapNotNull { it as? String }.toSet())
        }
        editor.apply()
    }

    // ─── queue ───────────────────────────────────────────────────────────────

    private fun queueFile(context: Context) = File(context.filesDir, QUEUE_FILE)

    fun enqueue(context: Context, record: JSONObject) {
        synchronized(lock) {
            try {
                val file = queueFile(context)
                file.appendText(record.toString().replace("\n", " ") + "\n")
                trimIfNeeded(file)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to enqueue capture", e)
            }
        }
    }

    /** Drops the oldest records once the queue grows past [MAX_RECORDS]. */
    private fun trimIfNeeded(file: File) {
        try {
            val lines = file.readLines()
            if (lines.size <= MAX_RECORDS) return
            file.writeText(lines.takeLast(MAX_RECORDS).joinToString("\n") + "\n")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to trim capture queue", e)
        }
    }

    /**
     * Returns every queued record and clears the queue in the same critical
     * section, so a capture arriving mid-drain is either fully included or
     * stays for the next drain — never lost, never returned twice.
     */
    fun drain(context: Context): List<Map<String, Any?>> {
        synchronized(lock) {
            val file = queueFile(context)
            if (!file.exists()) return emptyList()
            val out = mutableListOf<Map<String, Any?>>()
            try {
                for (line in file.readLines()) {
                    if (line.isBlank()) continue
                    try {
                        out.add(jsonToMap(JSONObject(line)))
                    } catch (e: Exception) {
                        Log.w(TAG, "Skipping malformed capture record", e)
                    }
                }
                file.delete()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to drain capture queue", e)
            }
            return out
        }
    }

    fun queuedCount(context: Context): Int {
        synchronized(lock) {
            val file = queueFile(context)
            if (!file.exists()) return 0
            return try {
                file.readLines().count { it.isNotBlank() }
            } catch (e: Exception) {
                0
            }
        }
    }

    fun clear(context: Context) {
        synchronized(lock) {
            try {
                queueFile(context).delete()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to clear capture queue", e)
            }
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            val value = json.get(key)
            map[key] = when {
                value == JSONObject.NULL -> null
                value is JSONObject -> jsonToMap(value)
                value is JSONArray -> (0 until value.length()).map { value.get(it) }
                else -> value
            }
        }
        return map
    }
}
