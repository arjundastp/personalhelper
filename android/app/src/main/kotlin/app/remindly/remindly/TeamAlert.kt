package app.remindly.remindly

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import java.time.LocalTime

/**
 * Morning Teams alert (endpoint mode). Every day at the chosen time (default 8:20 AM, after the
 * Claude routine's 8 AM run) the phone fetches the new summary from your Worker. If it isn't there
 * yet, it tries again every 20 minutes until 11:30 AM. When it arrives, a notification shows the
 * items that need you, Pulse first. Already seen in the app = no notification.
 */
object TeamAlert {
    const val KIND = "team_check"
    const val DEFAULT_MIN = 8 * 60 + 20
    private const val RETRY_MINUTES = 20
    private const val LAST_TRY_MIN = 11 * 60 + 30
    private const val KEEP_DAYS = 10L
    private const val CH_TEAM = "daymate_team_v1"
    private const val NOTIF_ID = 42_001
    private const val CODE = 900_101

    private fun pending(ctx: Context, flags: Int): PendingIntent? = PendingIntent.getBroadcast(
        ctx, CODE,
        Intent(ctx, AlarmReceiver::class.java).setAction("app.remindly.TEAM.$KIND").putExtra("kind", KIND),
        flags or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun active(t: JSONObject) = t.optBoolean("enabled") && t.optString("mode") == "endpoint" &&
        t.optString("endpointUrl").isNotBlank() && t.optString("readKey").isNotBlank() && t.optBoolean("alertOn", true)

    private fun setAt(ctx: Context, at: Long) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val op = pending(ctx, PendingIntent.FLAG_UPDATE_CURRENT)!!
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (canExact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op) else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, op)
    }

    /** (Re)arms the next daily check from the saved Team settings, or cancels it. */
    fun arm(ctx: Context) {
        val t = Store.team(ctx)
        if (!active(t)) {
            pending(ctx, PendingIntent.FLAG_NO_CREATE)?.let { ctx.getSystemService(AlarmManager::class.java).cancel(it); it.cancel() }
            return
        }
        val at = Sprint.nextAt(t.optInt("alertMin", DEFAULT_MIN), (1..7).toSet(), System.currentTimeMillis()) ?: return
        setAt(ctx, at)
    }

    fun onFired(ctx: Context, done: BroadcastReceiver.PendingResult) {
        Thread {
            try { check(ctx) } catch (_: Throwable) { arm(ctx) } finally { done.finish() }
        }.start()
    }

    private fun check(ctx: Context) {
        val t = Store.team(ctx)
        if (!active(t)) { arm(ctx); return }
        val yesterday = LocalDate.now().minusDays(1).toString()
        val fetched = runCatching { fetch(t.optString("endpointUrl").trimEnd('/'), t.optString("readKey"), yesterday) }.getOrNull()
        val merged = if (fetched != null) merge(ctx, fetched) else Store.team(ctx)
        val latest = latest(merged)
        val arrived = latest != null && latest.optString("date") >= yesterday
        if (!arrived) {
            val now = LocalTime.now()
            if (now.hour * 60 + now.minute + RETRY_MINUTES <= LAST_TRY_MIN) {
                setAt(ctx, System.currentTimeMillis() + RETRY_MINUTES * 60_000L)
                return
            }
            arm(ctx)
            return
        }
        val date = latest!!.optString("date")
        val seen = merged.optString("seenDate", "")
        val notified = merged.optString("alertedDate", "")
        if (date > seen && date > notified) {
            notify(ctx, latest)
            Store.saveTeam(ctx, Store.team(ctx).put("alertedDate", date))
        }
        arm(ctx)
    }

    private fun fetch(base: String, key: String, since: String): JSONArray {
        val c = URL("$base/summaries?since=$since").openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 20_000
            c.readTimeout = 20_000
            c.setRequestProperty("Authorization", "Bearer $key")
            c.setRequestProperty("Accept", "application/json")
            if (c.responseCode != 200) error("HTTP ${c.responseCode}")
            return JSONArray(c.inputStream.bufferedReader().use { it.readText() })
        } finally {
            c.disconnect()
        }
    }

    /** Adds fetched summaries to the saved ones (same date = replaced) and keeps the last 10 days. */
    private fun merge(ctx: Context, fetched: JSONArray): JSONObject {
        val t = Store.team(ctx)
        val byDate = LinkedHashMap<String, JSONObject>()
        val old = t.optJSONArray("summaries") ?: JSONArray()
        for (i in 0 until old.length()) old.optJSONObject(i)?.let { byDate[it.optString("date")] = it }
        for (i in 0 until fetched.length()) fetched.optJSONObject(i)?.let { s ->
            if (s.optString("date").matches(Regex("\\d{4}-\\d{2}-\\d{2}"))) byDate[s.optString("date")] = s
        }
        val cutoff = LocalDate.now().minusDays(KEEP_DAYS).toString()
        val kept = JSONArray()
        byDate.values.filter { it.optString("date") >= cutoff }.sortedBy { it.optString("date") }.forEach { kept.put(it) }
        t.put("summaries", kept).put("lastFetched", System.currentTimeMillis())
        Store.saveTeam(ctx, t)
        return t
    }

    private fun latest(t: JSONObject): JSONObject? {
        val arr = t.optJSONArray("summaries") ?: return null
        return (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }.maxByOrNull { it.optString("date") }
    }

    private fun isPulse(s: String) = s.contains("pulse", ignoreCase = true)

    /** "Teams: 3 things for you" with the top items (Pulse first), then the most important highlights. */
    fun lines(summary: JSONObject): Pair<String, List<String>> {
        fun list(key: String, field: String?): List<String> {
            val a = summary.optJSONArray(key) ?: return emptyList()
            return (0 until a.length()).mapNotNull { i ->
                (if (field == null) a.optString(i) else a.optJSONObject(i)?.optString(field))?.trim()?.takeIf { it.isNotEmpty() }
            }
        }
        val actions = list("actions", "text").sortedByDescending { isPulse(it) }
        val highlights = list("highlights", null).sortedByDescending { isPulse(it) }
        val title = when {
            actions.isNotEmpty() -> "Teams: ${actions.size} thing${if (actions.size == 1) "" else "s"} for you"
            highlights.any { isPulse(it) } -> "Teams: Pulse updates from yesterday"
            else -> "Teams summary is ready"
        }
        val body = (actions.take(4) + highlights.filter { it !in actions }.take((5 - actions.size).coerceAtLeast(1))).take(5)
        return title to body.ifEmpty { listOf("No Teams messages yesterday.") }
    }

    private fun notify(ctx: Context, summary: JSONObject) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CH_TEAM) == null) {
            nm.createNotificationChannel(NotificationChannel(CH_TEAM, "Teams summary", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Morning alert with the Teams messages that need you"
            })
        }
        val (title, body) = lines(summary)
        val open = PendingIntent.getActivity(
            ctx, NOTIF_ID,
            Intent(ctx, MainActivity::class.java).putExtra("openTeam", true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val style = Notification.InboxStyle().setBigContentTitle(title)
        body.forEach { style.addLine(it) }
        val n = Notification.Builder(ctx, CH_TEAM)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(title)
            .setContentText(body.first())
            .setStyle(style)
            .setColor(0xFF00A884.toInt())
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(NOTIF_ID, n) }
    }

    /** "Send a test alert" in Team settings: shows the notification for the latest saved summary. */
    fun test(ctx: Context): Boolean {
        val s = latest(Store.team(ctx)) ?: return false
        notify(ctx, s)
        return true
    }
}
