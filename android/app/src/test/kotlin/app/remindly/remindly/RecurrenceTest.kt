package app.remindly.remindly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class RecurrenceTest {
    private val zone = ZoneId.of("Asia/Kolkata")
    private fun ms(s: String) = LocalDateTime.parse(s).atZone(zone).toInstant().toEpochMilli()
    private fun dt(m: Long?) = m?.let { java.time.Instant.ofEpochMilli(it).atZone(zone).toLocalDateTime().toString() }
    private fun r(start: String, h: Int, m: Int, rule: RepeatRule) = Reminder(id = 1, startDate = start, hour = h, minute = m, repeat = rule)
    private fun next(rem: Reminder, after: String) = dt(Recurrence.next(rem, ms(after), zone))

    @Test fun once() {
        val x = r("2026-11-25", 9, 30, RepeatRule("once"))
        assertEquals("2026-11-25T09:30", next(x, "2026-11-22T10:00"))
        assertNull(next(x, "2026-11-25T09:30"))
    }

    @Test fun dailyEveryTwoDays() {
        val x = r("2026-11-20", 8, 0, RepeatRule("daily", 2))
        assertEquals("2026-11-20T08:00", next(x, "2026-11-01T00:00"))
        assertEquals("2026-11-22T08:00", next(x, "2026-11-20T08:00"))
        assertEquals("2026-11-24T08:00", next(x, "2026-11-22T09:00"))
    }

    @Test fun weeklyWeekdays() {
        // Mon, Wed, Fri at 7:00; 2026-11-22 is a Sunday
        val x = r("2026-11-01", 7, 0, RepeatRule("weekly", 1, listOf(1, 3, 5)))
        assertEquals("2026-11-23T07:00", next(x, "2026-11-22T12:00"))
        assertEquals("2026-11-25T07:00", next(x, "2026-11-23T07:00"))
        assertEquals("2026-11-30T07:00", next(x, "2026-11-27T07:00"))
    }

    @Test fun weeklyEveryOtherWeek() {
        // start Mon 2026-11-02, every 2 weeks on Monday
        val x = r("2026-11-02", 10, 0, RepeatRule("weekly", 2, listOf(1)))
        assertEquals("2026-11-16T10:00", next(x, "2026-11-02T10:00"))
        assertEquals("2026-11-30T10:00", next(x, "2026-11-16T10:00"))
    }

    @Test fun monthlyClampsShortMonths() {
        val x = r("2026-01-31", 9, 0, RepeatRule("monthly", 1))
        assertEquals("2026-02-28T09:00", next(x, "2026-01-31T09:00"))
        assertEquals("2026-03-31T09:00", next(x, "2026-02-28T09:00"))
    }

    @Test fun everySixMonthsLikePollutionCheck() {
        val x = r("2026-03-10", 10, 0, RepeatRule("monthly", 6))
        assertEquals("2026-09-10T10:00", next(x, "2026-03-10T10:00"))
        assertEquals("2027-03-10T10:00", next(x, "2026-11-22T00:00"))
    }

    @Test fun yearlyLeapDay() {
        val x = r("2028-02-29", 0, 5, RepeatRule("yearly", 1))
        assertEquals("2029-02-28T00:05", next(x, "2028-03-01T00:00"))
    }

    @Test fun hourlyWindow() {
        // drink water every 2h from 8:00 to 22:00
        val x = r("2026-11-20", 8, 0, RepeatRule("hourly", 120, windowEnd = 22 * 60))
        assertEquals("2026-11-22T14:00", next(x, "2026-11-22T13:10"))
        assertEquals("2026-11-22T22:00", next(x, "2026-11-22T20:00"))
        assertEquals("2026-11-23T08:00", next(x, "2026-11-22T22:00"))
    }

    @Test fun endDateStops() {
        val x = r("2026-11-20", 8, 0, RepeatRule("daily", 1, endDate = "2026-11-23"))
        assertEquals("2026-11-23T08:00", next(x, "2026-11-22T09:00"))
        assertNull(next(x, "2026-11-23T08:00"))
    }

    @Test fun jsonRoundTrip() {
        val x = r("2026-11-20", 8, 15, RepeatRule("weekly", 1, listOf(2, 4), null, "2027-01-01")).copy(title = "Pills", nextTrigger = 5L)
        assertEquals(x, Reminder.fromJson(org.json.JSONObject(x.toJson().toString())))
    }
}
