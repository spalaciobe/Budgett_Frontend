package com.budgett.budgett_frontend.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.budgett.budgett_frontend.MainActivity
import com.budgett.budgett_frontend.R
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget: which credit card to use for a purchase made today.
 *
 * Runs with no Flutter engine, so it does no cycle math. The app stores a
 * per-day schedule (see CardWidgetStore) and this only shows today's entry —
 * which is why it stays right across a cut-off date without the app being
 * opened. An alarm just after midnight flips it to the new day; the hourly
 * updatePeriodMillis is the fallback when Doze delays that alarm.
 */
class BestCardWidgetProvider : AppWidgetProvider() {

    companion object {
        /** Redraws every placed instance; called after Flutter pushes data. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, BestCardWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            render(context, manager, ids)
            scheduleMidnightRefresh(context, ids)
        }

        /** Below this height (dp) the widget is one row tall: 2x1. */
        private const val COMPACT_MAX_HEIGHT_DP = 100

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            ids: IntArray,
        ) {
            for (id in ids) manager.updateAppWidget(id, viewsFor(context, manager, id))
        }

        /**
         * Android 12+ takes both layouts and swaps them itself as the widget is
         * resized. Older launchers only report the size, so the layout is
         * chosen here and re-chosen in onAppWidgetOptionsChanged.
         */
        private fun viewsFor(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
        ): RemoteViews {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                return RemoteViews(
                    mapOf(
                        SizeF(100f, 40f) to buildViews(context, compact = true),
                        SizeF(100f, COMPACT_MAX_HEIGHT_DP.toFloat()) to
                            buildViews(context, compact = false),
                    ),
                )
            }
            // In portrait the usable height is MAX_HEIGHT; MIN_HEIGHT is the
            // landscape one.
            val height = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            val compact = height in 1 until COMPACT_MAX_HEIGHT_DP
            return buildViews(context, compact)
        }

        private fun buildViews(context: Context, compact: Boolean): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                if (compact) R.layout.widget_best_card_small else R.layout.widget_best_card,
            )

            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)

            val snapshot = CardWidgetStore.load(context)?.let {
                try {
                    JSONObject(it)
                } catch (_: Exception) {
                    null
                }
            }
            if (snapshot == null) {
                showMessage(views, "Open Budgett", "Sign in to see which card to use today")
                return views
            }

            when (snapshot.optString("status")) {
                "noCards" -> {
                    showMessage(views, "No credit cards", "Add one in Budgett to get a pick")
                    return views
                }
                "noRules" -> {
                    showMessage(
                        views,
                        "Set your cut-off dates",
                        "Add cut-off and payment days to your cards in Budgett",
                    )
                    return views
                }
            }

            val cards = todaysCards(snapshot.optJSONArray("days"))
            if (cards == null || cards.length() == 0) {
                showMessage(views, "Open Budgett", "Open the app to refresh this widget")
                return views
            }

            val best = cards.getJSONObject(0)
            val days = best.optInt("daysToPay")
            val dayWord = if (days == 1) "day" else "days"
            views.setTextViewText(R.id.card_name, best.optString("name"))
            views.setViewVisibility(R.id.days, View.VISIBLE)

            if (compact) {
                // One row: the answer and its date, no runners-up.
                views.setTextViewText(R.id.days, "$days $dayWord")
                val dueShort = best.optString("dueShort")
                    .ifEmpty { best.optString("dueLabel").removePrefix("Due ") }
                views.setTextViewText(R.id.due, "· $dueShort")
                return views
            }

            views.setTextViewText(R.id.days, "$days $dayWord to pay")
            views.setTextViewText(R.id.due, best.optString("dueLabel"))

            val others = (1 until cards.length()).map {
                val c = cards.getJSONObject(it)
                "${c.optString("name")} ${c.optInt("daysToPay")}d"
            }
            if (others.isEmpty()) {
                views.setViewVisibility(R.id.others, View.GONE)
            } else {
                views.setTextViewText(R.id.others, "Next: " + others.joinToString(" · "))
                views.setViewVisibility(R.id.others, View.VISIBLE)
            }
            return views
        }

        private fun showMessage(views: RemoteViews, title: String, body: String) {
            views.setTextViewText(R.id.card_name, title)
            views.setViewVisibility(R.id.days, View.GONE)
            views.setTextViewText(R.id.due, body)
            views.setViewVisibility(R.id.others, View.GONE)
        }

        private fun todaysCards(days: JSONArray?): JSONArray? {
            if (days == null) return null
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            for (i in 0 until days.length()) {
                val entry = days.getJSONObject(i)
                if (entry.optString("date") == today) return entry.optJSONArray("cards")
            }
            return null
        }

        /**
         * One inexact alarm a minute past midnight. Inexact needs no
         * SCHEDULE_EXACT_ALARM permission, and a few minutes' delay is harmless:
         * nobody buys much at 00:01.
         */
        private fun scheduleMidnightRefresh(context: Context, ids: IntArray) {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val intent = Intent(context, BestCardWidgetProvider::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            val pending = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val next = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 1)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            alarm.set(AlarmManager.RTC, next.timeInMillis, pending)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        render(context, appWidgetManager, appWidgetIds)
        scheduleMidnightRefresh(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // Resized between 2x1 and 2x2 (only matters before Android 12).
        render(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onDisabled(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, BestCardWidgetProvider::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarm.cancel(pending)
    }
}
