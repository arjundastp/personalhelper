package app.remindly.remindly

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.io.File

/**
 * Team summary without any sign-in: when the user grants DayMate "Notification access", this
 * collects ONLY Microsoft Teams notifications that appear on the phone, so they can be summarised
 * on the phone. Nothing is sent anywhere. Notifications of every other app are ignored.
 *
 * Collected text is kept in a private file for at most [KEEP_DAYS] days (enough for "yesterday"),
 * separate from the app's data, so it is never part of a backup.
 */
class TeamsListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in TEAMS_PACKAGES) return
        if (!TeamsInbox.collecting(this)) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return // "3 new messages" roll-ups
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return // calls, "Teams is running"
        val e = n.extras ?: return
        val conversation = e.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
        val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString()

        // Chat-style notifications carry a list of messages with their senders.
        val messages = messagesOf(e)
        if (messages.isNotEmpty()) {
            val chat = conversation ?: title ?: "Teams chat"
            messages.forEach { (sender, text) -> TeamsInbox.add(this, sbn.postTime, chat, sender ?: title, text) }
            return
        }
        val text = (e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: e.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: return
        TeamsInbox.add(this, sbn.postTime, conversation ?: title ?: "Teams", title, text)
    }

    @Suppress("DEPRECATION")
    private fun messagesOf(e: Bundle): List<Pair<String?, String>> {
        val arr = e.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return emptyList()
        return arr.mapNotNull { p ->
            val b = p as? Bundle ?: return@mapNotNull null
            val text = b.getCharSequence("text")?.toString() ?: return@mapNotNull null
            val sender = (b.get("sender_person") as? android.app.Person)?.name?.toString() ?: b.getCharSequence("sender")?.toString()
            sender to text
        }
    }

    companion object {
        val TEAMS_PACKAGES = setOf("com.microsoft.teams", "com.microsoft.teams2")

        fun hasAccess(ctx: Context): Boolean {
            val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(ctx, TeamsListener::class.java)
            return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
        }
    }
}

/** Private, short-lived store of collected Teams notification text (one JSON object per line). */
object TeamsInbox {
    private const val FILE = "teams_inbox.jsonl"
    const val KEEP_DAYS = 2
    private val lock = Any()
    private val recent = ArrayDeque<String>() // de-duplicates repeated posts of the same message

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    fun collecting(ctx: Context): Boolean {
        val t = Store.team(ctx)
        return t.optBoolean("enabled") && t.optString("mode") == "notifications"
    }

    fun add(ctx: Context, at: Long, chat: String, sender: String?, text: String) = synchronized(lock) {
        val clean = text.replace(Regex("\\s+"), " ").trim()
        if (clean.isEmpty()) return@synchronized
        val key = "$chat|$sender|$clean"
        if (key in recent) return@synchronized
        recent.addLast(key)
        if (recent.size > 200) recent.removeFirst()
        val line = JSONObject().put("at", at).put("chat", chat).put("sender", sender ?: JSONObject.NULL).put("text", clean)
        file(ctx).appendText(line.toString() + "\n")
    }

    /** Entries between [from] and [to] (epoch ms); also drops anything older than [KEEP_DAYS] days. */
    fun between(ctx: Context, from: Long, to: Long): List<JSONObject> = synchronized(lock) {
        val f = file(ctx)
        if (!f.exists()) return@synchronized emptyList()
        val cutoff = System.currentTimeMillis() - KEEP_DAYS * 24 * 3600_000L
        val all = f.readLines().mapNotNull { runCatching { JSONObject(it) }.getOrNull() }
        val kept = all.filter { it.optLong("at") >= cutoff }
        if (kept.size != all.size) f.writeText(kept.joinToString("") { it.toString() + "\n" })
        kept.filter { it.optLong("at") in from until to }
    }

    fun countSince(ctx: Context, from: Long): Int = between(ctx, from, Long.MAX_VALUE).size

    fun clear(ctx: Context) = synchronized(lock) {
        file(ctx).delete()
        recent.clear()
    }
}
