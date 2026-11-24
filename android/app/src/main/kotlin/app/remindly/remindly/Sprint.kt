package app.remindly.remindly

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId

/**
 * Daily Sprint: an optional work-day planner. The Flutter side owns the task list (stored as one
 * JSON object under "sprint" in [Store]); this side only schedules its two daily prompts:
 *  - morning: a gentle "plan your day" notification
 *  - evening: a full-screen "How did today go?" alert while today still has unanswered tasks
 */
object Sprint {
    const val KIND_MORNING = "sprint_morning"
    const val KIND_EVENING = "sprint_evening"
    const val KIND_SNOOZE = "sprint_snooze"
    /** RingRequest id used for the evening alert (reminders use ids >= 1, the test alert -1). */
    const val RING_ID = -2
    const val CATEGORY = "sprint"

    const val DEFAULT_MORNING = 10 * 60 + 30 // 10:30 AM
    const val DEFAULT_EVENING = 18 * 60 + 30 // 6:30 PM
    private const val CH_SPRINT = "remindly_sprint_v1"
    private const val NOTIF_MORNING = 41_001
    private const val NOTIF_REVIEW = 41_002

    private fun code(kind: String) = when (kind) {
        KIND_MORNING -> 900_001
        KIND_EVENING -> 900_002
        else -> 900_003
    }

    private fun pending(ctx: Context, kind: String, flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        ctx, code(kind),
        Intent(ctx, AlarmReceiver::class.java).setAction("app.remindly.SPRINT.$kind").putExtra("kind", kind),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun set(ctx: Context, kind: String, at: Long, alarmClock: Boolean) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val op = pending(ctx, kind, PendingIntent.FLAG_UPDATE_CURRENT)!!
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        when {
            canExact && alarmClock -> {
                val show = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
                am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), op)
            }
            canExact -> am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
            else -> am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
        }
    }

    private fun cancel(ctx: Context, kind: String) {
        pending(ctx, kind, PendingIntent.FLAG_NO_CREATE)?.let {
            ctx.getSystemService(AlarmManager::class.java).cancel(it); it.cancel()
        }
    }

    private fun workdays(s: JSONObject): Set<Int> {
        val arr = s.optJSONArray("workdays") ?: return setOf(1, 2, 3, 4, 5)
        return (0 until arr.length()).map { arr.getInt(it) }.toSet()
    }

    /** Next time [minuteOfDay] falls on a work day, strictly after [after]. */
    fun nextAt(minuteOfDay: Int, days: Set<Int>, after: Long, zone: ZoneId = ZoneId.systemDefault()): Long? {
        if (days.isEmpty()) return null
        val start = java.time.Instant.ofEpochMilli(after).atZone(zone).toLocalDateTime()
        for (i in 0..7) {
            val d = start.toLocalDate().plusDays(i.toLong())
            if (d.dayOfWeek.value !in days) continue
            val t = d.atStartOfDay().plusMinutes(minuteOfDay.toLong())
            if (t.isAfter(start)) return t.atZone(zone).toInstant().toEpochMilli()
        }
        return null
    }

    /** (Re)arms the morning and evening prompts from the saved sprint settings. */
    fun arm(ctx: Context) {
        val s = Store.sprint(ctx)
        val now = System.currentTimeMillis()
        val enabled = s.optBoolean("enabled", false)
        val days = workdays(s)
        val morning = if (enabled && s.optBoolean("morningOn", true)) nextAt(s.optInt("morningMin", DEFAULT_MORNING), days, now) else null
        val evening = if (enabled && s.optBoolean("eveningOn", true)) nextAt(s.optInt("eveningMin", DEFAULT_EVENING), days, now) else null
        if (morning != null) set(ctx, KIND_MORNING, morning, alarmClock = false) else cancel(ctx, KIND_MORNING)
        if (evening != null) set(ctx, KIND_EVENING, evening, alarmClock = true) else cancel(ctx, KIND_EVENING)
        if (!enabled) cancel(ctx, KIND_SNOOZE)
    }

    fun snooze(ctx: Context, minutes: Int) =
        set(ctx, KIND_SNOOZE, System.currentTimeMillis() + minutes * 60_000L, alarmClock = true)

    /** (planned today, done today, still unanswered today) */
    fun todayCounts(ctx: Context): Triple<Int, Int, Int> {
        val today = LocalDate.now().toString()
        val tasks = Store.sprint(ctx).optJSONArray("tasks") ?: return Triple(0, 0, 0)
        var total = 0; var done = 0; var open = 0
        for (i in 0 until tasks.length()) {
            val t = tasks.getJSONObject(i)
            if (t.optString("date") != today) continue
            total++
            when (t.optString("status", "open")) {
                "done" -> done++
                "open" -> open++
            }
        }
        return Triple(total, done, open)
    }

    fun onFired(ctx: Context, kind: String) {
        val s = Store.sprint(ctx)
        if (!s.optBoolean("enabled", false)) { arm(ctx); return }
        when (kind) {
            KIND_MORNING -> {
                val (total, _, _) = todayCounts(ctx)
                notify(
                    ctx, NOTIF_MORNING, "Plan your day",
                    if (total == 0) "What will you get done today? Tap to add your tasks."
                    else "You have $total task${if (total == 1) "" else "s"} planned for today. Tap to see them.",
                    "openSprint",
                )
                arm(ctx)
            }
            KIND_EVENING, KIND_SNOOZE -> {
                if (kind == KIND_EVENING) arm(ctx)
                val (total, done, open) = todayCounts(ctx)
                if (open == 0) return // nothing planned, or everything already answered
                val notes = "You planned $total task${if (total == 1) "" else "s"} and ticked $done. " +
                    "Tell me about the other $open."
                AlarmService.ring(ctx, RingRequest(
                    id = RING_ID, title = "How did today go?", notes = notes, category = CATEGORY,
                    soundUri = s.optStringOrNull("soundUri") ?: Store.settings(ctx).optStringOrNull("defaultSoundUri"),
                    soundOn = s.optBoolean("soundOn", true), vibrate = true, snoozeMinutes = 30,
                    dueAt = System.currentTimeMillis(), missed = false, attempt = 0,
                ))
            }
        }
    }

    /** Shown when the evening alert rang out without an answer. */
    fun postReviewReminder(ctx: Context) = notify(
        ctx, NOTIF_REVIEW, "Update today's tasks",
        "Tap to mark what got done, what didn't, and what is paused.", "openSprintReview",
    )

    private fun notify(ctx: Context, id: Int, title: String, text: String, action: String) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CH_SPRINT) == null) {
            nm.createNotificationChannel(NotificationChannel(CH_SPRINT, "Daily Sprint", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Morning planning nudge and evening check-in"
            })
        }
        val open = PendingIntent.getActivity(
            ctx, id,
            Intent(ctx, MainActivity::class.java).putExtra(action, true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = Notification.Builder(ctx, CH_SPRINT)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setColor(Categories.color(CATEGORY))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(id, n) }
    }

}
