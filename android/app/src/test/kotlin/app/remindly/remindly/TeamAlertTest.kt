package app.remindly.remindly

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TeamAlertTest {
    private fun summary(actions: List<String>, highlights: List<String>) = JSONObject()
        .put("date", "2026-11-24")
        .put("actions", JSONArray(actions.map { JSONObject().put("text", it).put("source", "Chat") }))
        .put("highlights", JSONArray(highlights))

    @Test
    fun pulseItemsComeFirst() {
        val (title, lines) = TeamAlert.lines(summary(
            listOf("Ravi: review the payment PR", "Pulse: approve the release notes by 11 AM"),
            listOf("Release moved to Thursday", "Pulse: dashboard latency fixed"),
        ))
        assertEquals("Teams: 2 things for you", title)
        assertEquals("Pulse: approve the release notes by 11 AM", lines.first())
        assertTrue(lines.contains("Pulse: dashboard latency fixed"))
        assertTrue(lines.size <= 5)
    }

    @Test
    fun noActionsButPulseHighlights() {
        val (title, lines) = TeamAlert.lines(summary(emptyList(), listOf("Team lunch on Friday", "Pulse: v2 launched")))
        assertEquals("Teams: Pulse updates from yesterday", title)
        assertEquals("Pulse: v2 launched", lines.first())
    }

    @Test
    fun emptySummary() {
        val (title, lines) = TeamAlert.lines(summary(emptyList(), emptyList()))
        assertEquals("Teams summary is ready", title)
        assertEquals(listOf("No Teams messages yesterday."), lines)
    }
}
