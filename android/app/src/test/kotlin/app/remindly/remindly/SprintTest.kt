package app.remindly.remindly

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class SprintTest {
    private val zone = ZoneId.of("Asia/Kolkata")
    private fun ms(s: String) = LocalDateTime.parse(s).atZone(zone).toInstant().toEpochMilli()
    private fun dt(m: Long?) = m?.let { java.time.Instant.ofEpochMilli(it).atZone(zone).toLocalDateTime().toString() }
    private val weekdays = setOf(1, 2, 3, 4, 5)

    @Test fun eveningLaterToday() =
        assertEquals("2026-11-24T18:30", dt(Sprint.nextAt(18 * 60 + 30, weekdays, ms("2026-11-24T10:00"), zone)))

    @Test fun eveningPassedGoesToNextWorkday() =
        assertEquals("2026-11-25T18:30", dt(Sprint.nextAt(18 * 60 + 30, weekdays, ms("2026-11-24T18:30"), zone)))

    @Test fun fridayEveningSkipsWeekend() = // 2026-11-27 is a Friday
        assertEquals("2026-11-30T10:30", dt(Sprint.nextAt(10 * 60 + 30, weekdays, ms("2026-11-27T11:00"), zone)))

    @Test fun noWorkdays() = assertNull(Sprint.nextAt(600, emptySet(), ms("2026-11-24T10:00"), zone))
}
