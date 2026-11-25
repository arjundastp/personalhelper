package app.remindly.remindly

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Talks to AlarmManager. Every reminder has up to three alarm "slots":
 *   regular (next occurrence), snooze, and missed (re-alert after the phone was off).
 * We use setAlarmClock(): it is exact, fires in Doze, and is exempt from background limits.
 */
object Scheduler {
    const val KIND_REGULAR = "regular"
    const val KIND_SNOOZE = "snooze"
    const val KIND_MISSED = "missed"

    /** Reminders that were due more than this long ago are "missed" when we find them. */
    private const val MISSED_GRACE_MS = 60_000L
    /** Missed reminders older than this are only logged, not rung (e.g. phone off for days). */
    private const val MISSED_RING_WINDOW_MS = 24 * 60 * 60_000L

    private fun requestCode(id: Int, kind: String) = id * 4 + when (kind) {
        KIND_SNOOZE -> 1
        KIND_MISSED -> 2
        else -> 0
    }

    private fun pending(ctx: Context, id: Int, kind: String, dueAt: Long, flags: Int): PendingIntent? {
        val intent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = "app.remindly.ALARM.$kind.$id"
            putExtra("id", id); putExtra("kind", kind); putExtra("dueAt", dueAt)
        }
        return PendingIntent.getBroadcast(ctx, requestCode(id, kind), intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun setAlarm(ctx: Context, id: Int, kind: String, at: Long, dueAt: Long = at) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val op = pending(ctx, id, kind, dueAt, PendingIntent.FLAG_UPDATE_CURRENT)!!
        val show = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (canExact) {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), op)
        } else {
            // Fallback: still wakes the device, may be delayed a few minutes by the OS.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
        }
    }

    private fun cancel(ctx: Context, id: Int, kind: String) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        pending(ctx, id, kind, 0, PendingIntent.FLAG_NO_CREATE)?.let { am.cancel(it); it.cancel() }
    }

    /** Recomputes the next occurrence from now, (re)arms alarms and returns the updated reminder (not saved). */
    fun arm(ctx: Context, r: Reminder, now: Long = System.currentTimeMillis()): Reminder {
        val next = if (r.enabled) Recurrence.next(r, now) else null
        if (next != null) setAlarm(ctx, r.id, KIND_REGULAR, next) else cancel(ctx, r.id, KIND_REGULAR)
        val snooze = r.snoozedUntil?.takeIf { it > now }
        if (snooze != null) setAlarm(ctx, r.id, KIND_SNOOZE, snooze) else cancel(ctx, r.id, KIND_SNOOZE)
        return r.copy(nextTrigger = next, snoozedUntil = snooze)
    }

    fun save(ctx: Context, r: Reminder): Reminder {
        val withId = if (r.id <= 0) Store.put(ctx, r) else r
        return Store.put(ctx, arm(ctx, withId))
    }

    fun remove(ctx: Context, id: Int) {
        listOf(KIND_REGULAR, KIND_SNOOZE, KIND_MISSED).forEach { cancel(ctx, id, it) }
        Store.delete(ctx, id)
    }

    fun snooze(ctx: Context, id: Int, minutes: Int, auto: Boolean, attempt: Int) {
        val r = Store.get(ctx, id) ?: return
        val until = System.currentTimeMillis() + minutes * 60_000L
        Store.put(ctx, arm(ctx, r.copy(snoozedUntil = until, snoozeAttempt = if (auto) attempt else 0)))
    }

    /**
     * Re-arms everything (after boot, app update, time change, or app launch) and detects reminders
     * that should have rung while the phone was off / the app was force-stopped. Those get a
     * "missed" alert a few seconds from now so the user sees them as soon as the phone is active.
     */
    fun resync(ctx: Context, ringMissed: Boolean) {
        Sprint.arm(ctx)
        TeamAlert.arm(ctx)
        val now = System.currentTimeMillis()
        var delay = 3_000L
        for (r in Store.reminders(ctx)) {
            val due = listOfNotNull(r.nextTrigger, r.snoozedUntil).minOrNull()
            val wasMissed = r.enabled && due != null && due < now - MISSED_GRACE_MS
            var updated = r
            if (wasMissed && due != null) {
                if (r.repeat.type == "once") updated = updated.copy(enabled = false)
                updated = updated.copy(lastFired = due, snoozedUntil = null)
                if (ringMissed && now - due < MISSED_RING_WINDOW_MS) {
                    setAlarm(ctx, r.id, KIND_MISSED, now + delay, dueAt = due)
                    delay += 2_000L
                } else {
                    Store.log(ctx, r.id, r.title, r.category, due, "missed")
                }
            }
            Store.put(ctx, arm(ctx, updated, now))
        }
    }

    /** Called by AlarmReceiver. Returns the ring request to show, or null if the alarm is stale. */
    fun onFired(ctx: Context, id: Int, kind: String, dueAt: Long): RingRequest? {
        val r = Store.get(ctx, id) ?: return null
        val now = System.currentTimeMillis()
        val settings = Store.settings(ctx)
        return when (kind) {
            KIND_REGULAR -> {
                val scheduled = r.nextTrigger ?: return null
                if (!r.enabled || scheduled > now + 60_000L) return null // stale / rescheduled
                var updated = r.copy(lastFired = scheduled, snoozedUntil = null, snoozeAttempt = 0)
                if (r.repeat.type == "once") updated = updated.copy(enabled = false)
                Store.put(ctx, arm(ctx, updated, maxOf(now, scheduled)))
                RingRequest.from(r, settings, scheduled, missed = false, attempt = 0)
            }
            KIND_SNOOZE -> {
                val until = r.snoozedUntil ?: return null
                if (until > now + 60_000L) return null
                Store.put(ctx, r.copy(snoozedUntil = null))
                RingRequest.from(r, settings, r.lastFired ?: until, missed = false, attempt = r.snoozeAttempt)
            }
            else -> RingRequest.from(r, settings, dueAt, missed = true, attempt = 0)
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        val kind = intent.getStringExtra("kind") ?: Scheduler.KIND_REGULAR
        val dueAt = intent.getLongExtra("dueAt", System.currentTimeMillis())
        if (kind.startsWith("sprint_")) { Sprint.onFired(ctx, kind); return }
        if (kind == TeamAlert.KIND) { TeamAlert.onFired(ctx, goAsync()); return }
        if (id < 0 && kind != "test") return
        val req = if (kind == "test") RingRequest.test(ctx) else Scheduler.onFired(ctx, id, kind, dueAt)
        req?.let { AlarmService.ring(ctx, it) }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> Scheduler.resync(ctx, ringMissed = true)
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> Scheduler.resync(ctx, ringMissed = false)
        }
    }
}

object TestAlarm {
    fun schedule(ctx: Context, seconds: Int) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val intent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = "app.remindly.ALARM.test"; putExtra("kind", "test")
        }
        val op = PendingIntent.getBroadcast(ctx, 999_999, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val at = System.currentTimeMillis() + seconds * 1000L
        val show = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (canExact) am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), op)
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
    }
}
