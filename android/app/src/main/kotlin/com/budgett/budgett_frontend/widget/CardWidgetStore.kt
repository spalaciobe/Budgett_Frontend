package com.budgett.budgett_frontend.widget

import android.content.Context

/**
 * The schedule the "Best card today" widget reads, in its own
 * SharedPreferences file — for the same reason as CaptureStore: a change in
 * how the shared_preferences plugin stores data must not blank the widget.
 *
 * The value is the JSON built by `buildCardWidgetSnapshot` in Dart; this side
 * never computes anything from it, it only picks today's entry.
 */
object CardWidgetStore {
    private const val PREFS = "budgett_card_widget"
    private const val KEY_SNAPSHOT = "snapshot"

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_SNAPSHOT, json).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY_SNAPSHOT).apply()
    }

    fun load(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT, null)
}
