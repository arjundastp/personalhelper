package app.remindly.remindly

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * Home-screen widget: a compact version of the app's Home screen (greeting, what needs you,
 * next reminder, today's Daily Sprint and the Teams summary). Everything is read from the
 * app's own data on the phone. It refreshes when that data changes and every 30 minutes.
 */
class DayMateWidget : AppWidgetProvider() {

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        val views = build(ctx)
        ids.forEach { mgr.updateAppWidget(it, views) }
    }

    companion object {
        private val main = Handler(Looper.getMainLooper())

        fun component(ctx: Context) = ComponentName(ctx, DayMateWidget::class.java)

        fun count(ctx: Context): Int = runCatching { AppWidgetManager.getInstance(ctx).getAppWidgetIds(component(ctx)).size }.getOrDefault(0)

        /** Redraws every placed widget (cheap no-op when none are placed). Safe to call often. */
        fun refresh(ctx: Context) {
            val app = ctx.applicationContext
            main.removeCallbacksAndMessages(TOKEN)
            main.postAtTime({
                runCatching {
                    val mgr = AppWidgetManager.getInstance(app)
                    val ids = mgr.getAppWidgetIds(component(app))
                    if (ids.isNotEmpty()) {
                        val views = build(app)
                        ids.forEach { mgr.updateAppWidget(it, views) }
                    }
                }
            }, TOKEN, android.os.SystemClock.uptimeMillis() + 300)
        }

        private val TOKEN = Any()

        /** Asks the launcher to place the widget (Android 8+, most launchers incl. Samsung One UI). */
        fun requestPin(ctx: Context): Boolean {
            val mgr = AppWidgetManager.getInstance(ctx)
            if (!mgr.isRequestPinAppWidgetSupported) return false
            return mgr.requestPinAppWidget(component(ctx), null, null)
        }

        fun build(ctx: Context): RemoteViews {
            val v = RemoteViews(ctx.packageName, R.layout.widget_daymate)
            val now = LocalDateTime.now()
            val zone = ZoneId.systemDefault()
            val today = LocalDate.now()
            val settings = Store.settings(ctx)
            val sprint = Store.sprint(ctx)
            val team = Store.team(ctx)
            val sprintOn = sprint.optBoolean("enabled", false)
            val teamOn = team.optBoolean("enabled", false)

            // ---- greeting ----
            val name = settings.optString("userName", "").trim()
            val hello = when (now.hour) {
                in 5..11 -> "Good morning"
                in 12..16 -> "Good afternoon"
                in 17..21 -> "Good evening"
                else -> "Hello"
            }
            v.setTextViewText(R.id.w_greeting, if (name.isEmpty()) "$hello!" else "$hello, $name!")
            v.setTextViewText(R.id.w_date, today.format(DateTimeFormatter.ofPattern("EEEE, d MMMM", Locale.getDefault())))

            // ---- what needs you (same order as the app's Home screen) ----
            val items = ArrayList<String>()
            val history = Store.history(ctx)
            val missed = (0 until history.length()).map { history.getJSONObject(it) }
                .count { it.optString("status") == "missed" && !it.optBoolean("seen", true) }
            if (missed > 0) items += "$missed missed reminder${if (missed == 1) "" else "s"}"
            if (teamOn) {
                val actions = latestSummary(team)?.optJSONArray("actions")
                if (actions != null) {
                    val list = (0 until actions.length()).map { actions.getJSONObject(it).optString("text") }.filter { it.isNotBlank() }
                        .sortedByDescending { it.contains("pulse", ignoreCase = true) }
                    items += list
                }
            }
            var openToday = 0
            var doneToday = 0
            var totalToday = 0
            if (sprintOn) {
                val tasks = sprint.optJSONArray("tasks")
                val todayKey = today.toString()
                val cutoff = today.minusDays(14).toString()
                var unanswered: String? = null
                if (tasks != null) for (i in 0 until tasks.length()) {
                    val t = tasks.getJSONObject(i)
                    val date = t.optString("date")
                    val status = t.optString("status", "open")
                    if (date == todayKey) {
                        totalToday++
                        if (status == "done") doneToday++
                        if (status == "open") openToday++
                    } else if (status == "open" && date < todayKey && date >= cutoff && (unanswered == null || date > unanswered)) {
                        unanswered = date
                    }
                }
                if (unanswered != null) {
                    val d = LocalDate.parse(unanswered)
                    val label = if (d == today.minusDays(1)) "Yesterday" else d.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.getDefault())
                    items += "$label's tasks are not updated"
                }
                val evening = now.hour * 60 + now.minute >= sprint.optInt("eveningMin", 18 * 60 + 30)
                if (openToday > 0 && evening) items += "How did today go? $openToday to update"
            }
            if (items.isEmpty()) {
                v.setImageViewResource(R.id.att_icon, R.drawable.ic_w_ok)
                v.setTextViewText(R.id.att_title, "All clear")
                v.setTextViewText(R.id.att_sub, "Nothing needs you right now")
            } else {
                v.setImageViewResource(R.id.att_icon, R.drawable.ic_w_attention)
                v.setTextViewText(R.id.att_title, "${items.size} need${if (items.size == 1) "s" else ""} your attention")
                v.setTextViewText(R.id.att_sub, items.first() + if (items.size > 1) "  ·  +${items.size - 1} more" else "")
            }
            v.setTextViewText(R.id.w_line, line(now, items.isEmpty(), sprintOn, totalToday, doneToday))

            // ---- next reminder ----
            val nowMs = System.currentTimeMillis()
            val next = Store.reminders(ctx).filter { it.enabled }
                .mapNotNull { r -> listOfNotNull(r.snoozedUntil, r.nextTrigger).filter { it > nowMs }.minOrNull()?.let { r to it } }
                .minByOrNull { it.second }
            v.setTextViewText(
                R.id.next_text,
                if (next == null) "No reminders coming up"
                else "Next: ${next.first.title} · ${whenText(Instant.ofEpochMilli(next.second).atZone(zone).toLocalDateTime(), today)}",
            )

            // ---- today's tasks ----
            v.setViewVisibility(R.id.sprint_row, if (sprintOn) View.VISIBLE else View.GONE)
            if (sprintOn) {
                val leave = sprint.optJSONObject("leaves")?.optJSONObject(today.toString())
                v.setTextViewText(
                    R.id.sprint_text,
                    when {
                        leave != null -> when (leave.optString("type")) { "half" -> "Half day today"; "holiday" -> "Holiday today"; else -> "On leave today" }
                        totalToday == 0 -> "No tasks planned yet"
                        else -> "$doneToday of $totalToday tasks done"
                    },
                )
            }

            // ---- Teams ----
            v.setViewVisibility(R.id.team_row, if (teamOn) View.VISIBLE else View.GONE)
            if (teamOn) {
                val s = latestSummary(team)
                v.setTextViewText(
                    R.id.team_text,
                    if (s == null) "No Teams summary yet"
                    else {
                        val chats = s.optJSONArray("chats")?.length() ?: 0
                        val forYou = s.optJSONArray("actions")?.length() ?: 0
                        "Teams: $chats chat${if (chats == 1) "" else "s"} · $forYou for you"
                    },
                )
            }

            // Tap anywhere: open DayMate.
            val open = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            v.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(ctx, 7001, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
            return v
        }

        private fun latestSummary(team: JSONObject): JSONObject? {
            val arr = team.optJSONArray("summaries") ?: return null
            return (0 until arr.length()).map { arr.getJSONObject(it) }.maxByOrNull { it.optString("date") }
        }

        private fun whenText(t: LocalDateTime, today: LocalDate): String {
            val time = t.format(DateTimeFormatter.ofPattern("h:mm a", Locale.getDefault()))
            return when (t.toLocalDate()) {
                today -> time
                today.plusDays(1) -> "Tomorrow $time"
                else -> "${t.format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.getDefault()))} $time"
            }
        }

        private fun line(now: LocalDateTime, allClear: Boolean, sprintOn: Boolean, total: Int, done: Int): String = when {
            sprintOn && total > 0 && done == total -> "Everything on today's plan is done. Well earned!"
            now.dayOfWeek.value == 1 && now.hour < 12 -> "A fresh week begins. Set the tone today."
            now.dayOfWeek.value == 5 -> "Happy Friday! Finish strong."
            now.dayOfWeek.value >= 6 -> "Slow down and recharge this weekend."
            allClear -> "A calm mind gets more done."
            else -> "One thing at a time. You have got this."
        }
    }
}
