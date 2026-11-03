package com.budgett.budgett_frontend.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            ids: IntArray,
        ) {
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_best_card)

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
            views.setTextViewText(R.id.card_name, best.optString("name"))
            views.setTextViewText(
                R.id.days,
                if (days == 1) "1 day to pay" else "$days days to pay",
            )
            views.setViewVisibility(R.id.days, View.VISIBLE)
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
