package app.remindly.remindly

import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import kotlin.math.max
import kotlin.math.min

/**
 * How a reminder repeats.
 *
 * type:     once | daily | weekly | monthly | yearly | hourly
 * interval: every N days / weeks / months / years; for "hourly" it is the gap in MINUTES.
 * weekdays: for weekly, ISO day numbers 1 (Mon) .. 7 (Sun).
 * windowEnd: for hourly, last allowed minute-of-day (e.g. 22:00 -> 1320).
 * endDate:  optional last date (inclusive), ISO yyyy-MM-dd.
 */
data class RepeatRule(
    val type: String = "once",
    val interval: Int = 1,
    val weekdays: List<Int> = emptyList(),
    val windowEnd: Int? = null,
    val endDate: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("type", type)
        put("interval", interval)
        put("weekdays", JSONArray(weekdays))
        put("windowEnd", windowEnd ?: JSONObject.NULL)
        put("endDate", endDate ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(o: JSONObject?): RepeatRule {
            if (o == null) return RepeatRule()
            val days = o.optJSONArray("weekdays")
            return RepeatRule(
                type = o.optString("type", "once"),
                interval = max(1, o.optInt("interval", 1)),
                weekdays = if (days == null) emptyList() else (0 until days.length()).map { days.getInt(it) },
                windowEnd = if (o.isNull("windowEnd") || !o.has("windowEnd")) null else o.getInt("windowEnd"),
                endDate = o.optStringOrNull("endDate"),
            )
        }
    }
}

data class Reminder(
    val id: Int = 0,
    val title: String = "",
    val notes: String = "",
    val category: String = "custom",
    val startDate: String = LocalDate.now().toString(),
    val hour: Int = 9,
    val minute: Int = 0,
    val repeat: RepeatRule = RepeatRule(),
    val soundUri: String? = null,
    val soundName: String? = null,
    val vibrate: Boolean = true,
    val enabled: Boolean = true,
    val snoozeMinutes: Int = 10,
    val createdAt: Long = System.currentTimeMillis(),
    val nextTrigger: Long? = null,
    val snoozedUntil: Long? = null,
    val snoozeAttempt: Int = 0,
    val lastFired: Long? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("notes", notes)
        put("category", category)
        put("startDate", startDate)
        put("hour", hour)
        put("minute", minute)
        put("repeat", repeat.toJson())
        put("soundUri", soundUri ?: JSONObject.NULL)
        put("soundName", soundName ?: JSONObject.NULL)
        put("vibrate", vibrate)
        put("enabled", enabled)
        put("snoozeMinutes", snoozeMinutes)
        put("createdAt", createdAt)
        put("nextTrigger", nextTrigger ?: JSONObject.NULL)
        put("snoozedUntil", snoozedUntil ?: JSONObject.NULL)
        put("snoozeAttempt", snoozeAttempt)
        put("lastFired", lastFired ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(o: JSONObject): Reminder = Reminder(
            id = o.optInt("id", 0),
            title = o.optString("title", ""),
            notes = o.optString("notes", ""),
            category = o.optString("category", "custom"),
            startDate = o.optStringOrNull("startDate") ?: LocalDate.now().toString(),
            hour = o.optInt("hour", 9).coerceIn(0, 23),
            minute = o.optInt("minute", 0).coerceIn(0, 59),
            repeat = RepeatRule.fromJson(o.optJSONObject("repeat")),
            soundUri = o.optStringOrNull("soundUri"),
            soundName = o.optStringOrNull("soundName"),
            vibrate = o.optBoolean("vibrate", true),
            enabled = o.optBoolean("enabled", true),
            snoozeMinutes = o.optInt("snoozeMinutes", 10).coerceIn(1, 240),
            createdAt = o.optLong("createdAt", System.currentTimeMillis()),
            nextTrigger = o.optLongOrNull("nextTrigger"),
            snoozedUntil = o.optLongOrNull("snoozedUntil"),
            snoozeAttempt = o.optInt("snoozeAttempt", 0),
            lastFired = o.optLongOrNull("lastFired"),
        )
    }
}

fun JSONObject.optStringOrNull(key: String): String? =
    if (!has(key) || isNull(key)) null else optString(key).ifEmpty { null }

fun JSONObject.optLongOrNull(key: String): Long? =
    if (!has(key) || isNull(key)) null else optLong(key)

/** Computes occurrences of a reminder. This is the single source of truth for scheduling. */
object Recurrence {
    private const val MAX_LOOPS = 5000

    /** First occurrence strictly after [afterMillis], or null if there are no more. */
    fun next(r: Reminder, afterMillis: Long, zone: ZoneId = ZoneId.systemDefault()): Long? {
        val after = Instant.ofEpochMilli(afterMillis).atZone(zone).toLocalDateTime()
        val start = runCatching { LocalDate.parse(r.startDate) }.getOrDefault(LocalDate.now(zone))
        val time = LocalTime.of(r.hour, r.minute)
        val rule = r.repeat
        val n = max(1, rule.interval)
        val end = rule.endDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

        val found: LocalDateTime? = when (rule.type) {
            "daily" -> {
                var k = max(0L, ChronoUnit.DAYS.between(start, after.toLocalDate()) / n - 1)
                var res: LocalDateTime? = null
                var loops = 0
                while (res == null && loops++ < MAX_LOOPS) {
                    val dt = start.plusDays(k * n).atTime(time)
                    if (dt.isAfter(after)) res = dt
                    k++
                }
                res
            }
            "weekly" -> {
                val days = rule.weekdays.filter { it in 1..7 }.ifEmpty { listOf(start.dayOfWeek.value) }.toSet()
                val anchor = start.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                var d = if (after.toLocalDate().isAfter(start)) after.toLocalDate() else start
                var res: LocalDateTime? = null
                var loops = 0
                while (res == null && loops++ < 7 * n + 14) {
                    val monday = d.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                    val weeks = ChronoUnit.WEEKS.between(anchor, monday)
                    if (d.dayOfWeek.value in days && weeks % n == 0L) {
                        val dt = d.atTime(time)
                        if (dt.isAfter(after)) res = dt
                    }
                    d = d.plusDays(1)
                }
                res
            }
            "monthly", "yearly" -> {
                val step = if (rule.type == "yearly") 12L * n else n.toLong()
                val startYm = YearMonth.from(start)
                val dom = start.dayOfMonth
                var k = max(0L, ChronoUnit.MONTHS.between(startYm, YearMonth.from(after)) / step - 1)
                var res: LocalDateTime? = null
                var loops = 0
                while (res == null && loops++ < MAX_LOOPS) {
                    val ym = startYm.plusMonths(k * step)
                    val dt = ym.atDay(min(dom, ym.lengthOfMonth())).atTime(time)
                    if (dt.isAfter(after)) res = dt
                    k++
                }
                res
            }
            "hourly" -> {
                val step = max(5, n)
                val first = r.hour * 60 + r.minute
                val last = max(first, rule.windowEnd ?: (23 * 60 + 59))
                var d = if (after.toLocalDate().isAfter(start)) after.toLocalDate() else start
                var res: LocalDateTime? = null
                var days = 0
                while (res == null && days++ < 3) {
                    var m = first
                    while (m <= last && m < 24 * 60) {
                        val dt = d.atStartOfDay().plusMinutes(m.toLong())
                        if (dt.isAfter(after)) { res = dt; break }
                        m += step
                    }
                    d = d.plusDays(1)
                }
                res
            }
            else -> start.atTime(time).takeIf { it.isAfter(after) } // once
        }

        if (found == null) return null
        if (end != null && found.toLocalDate().isAfter(end)) return null
        return found.atZone(zone).toInstant().toEpochMilli()
    }

    fun upcoming(r: Reminder, fromMillis: Long, count: Int, zone: ZoneId = ZoneId.systemDefault()): List<Long> {
        val out = ArrayList<Long>()
        var cursor = fromMillis
        while (out.size < count) {
            val nx = next(r, cursor, zone) ?: break
            out.add(nx)
            cursor = nx
        }
        return out
    }
}
