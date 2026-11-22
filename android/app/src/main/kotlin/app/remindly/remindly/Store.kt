package app.remindly.remindly

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * All app data lives in one JSON file in the app's private storage.
 * Nothing ever leaves the phone (the app does not even request the INTERNET permission in release).
 */
object Store {
    private const val FILE = "remindly_data.json"
    private const val MAX_HISTORY = 300
    private val lock = Any()
    private var cache: JSONObject? = null

    /** Called after every change so the Flutter UI (if open) can refresh. */
    @Volatile var onChanged: (() -> Unit)? = null

    val DEFAULT_SETTINGS: JSONObject
        get() = JSONObject().apply {
            put("defaultSoundUri", SoundHelper.bundledUri("gentle_chime"))
            put("defaultSoundName", "Gentle Chime")
            put("ringMinutes", 2)          // how long one alert rings before auto-snoozing
            put("autoRepeat", 3)           // how many times an unanswered alert re-rings
            put("snoozeMinutes", 10)
            put("gradualVolume", true)
            put("ensureVolume", true)      // raise alarm volume to minVolume if it is lower
            put("minVolume", 70)           // percent
            put("overrideDnd", true)       // break through "Total silence" when access is granted
            put("vibrate", true)
            put("appLock", false)
            put("themeMode", "system")
            put("largeText", false)
            put("onboarded", false)
        }

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    private fun root(ctx: Context): JSONObject {
        cache?.let { return it }
        val f = file(ctx)
        val obj = runCatching { JSONObject(f.readText()) }.getOrNull() ?: JSONObject()
        if (!obj.has("nextId")) obj.put("nextId", 1)
        if (!obj.has("reminders")) obj.put("reminders", JSONArray())
        if (!obj.has("history")) obj.put("history", JSONArray())
        val settings = DEFAULT_SETTINGS
        obj.optJSONObject("settings")?.let { saved -> saved.keys().forEach { settings.put(it, saved.get(it)) } }
        obj.put("settings", settings)
        cache = obj
        return obj
    }

    private fun persist(ctx: Context) {
        val obj = cache ?: return
        val f = file(ctx)
        val tmp = File(f.parentFile, "$FILE.tmp")
        tmp.writeText(obj.toString())
        if (!tmp.renameTo(f)) { f.writeText(obj.toString()); tmp.delete() }
        onChanged?.invoke()
    }

    // ---------------- reminders ----------------

    fun reminders(ctx: Context): List<Reminder> = synchronized(lock) {
        val arr = root(ctx).getJSONArray("reminders")
        (0 until arr.length()).map { Reminder.fromJson(arr.getJSONObject(it)) }
    }

    fun get(ctx: Context, id: Int): Reminder? = reminders(ctx).firstOrNull { it.id == id }

    /** Inserts or replaces. Returns the stored reminder (with an id assigned). */
    fun put(ctx: Context, r: Reminder): Reminder = synchronized(lock) {
        val obj = root(ctx)
        val stored = if (r.id <= 0) {
            val id = obj.getInt("nextId")
            obj.put("nextId", id + 1)
            r.copy(id = id)
        } else r
        val arr = obj.getJSONArray("reminders")
        val out = JSONArray()
        var replaced = false
        for (i in 0 until arr.length()) {
            val item = arr.getJSONObject(i)
            if (item.optInt("id") == stored.id) { out.put(stored.toJson()); replaced = true } else out.put(item)
        }
        if (!replaced) out.put(stored.toJson())
        obj.put("reminders", out)
        persist(ctx)
        stored
    }

    fun delete(ctx: Context, id: Int) = synchronized(lock) {
        val obj = root(ctx)
        val arr = obj.getJSONArray("reminders")
        val out = JSONArray()
        for (i in 0 until arr.length()) if (arr.getJSONObject(i).optInt("id") != id) out.put(arr.getJSONObject(i))
        obj.put("reminders", out)
        persist(ctx)
    }

    // ---------------- settings ----------------

    fun settings(ctx: Context): JSONObject = synchronized(lock) { JSONObject(root(ctx).getJSONObject("settings").toString()) }

    fun saveSettings(ctx: Context, update: JSONObject) = synchronized(lock) {
        val s = root(ctx).getJSONObject("settings")
        update.keys().forEach { s.put(it, update.get(it)) }
        persist(ctx)
    }

    // ---------------- history ----------------

    /** status: done | snoozed | auto_snoozed | missed */
    fun log(ctx: Context, reminderId: Int, title: String, category: String, dueAt: Long, status: String) = synchronized(lock) {
        val obj = root(ctx)
        val arr = obj.getJSONArray("history")
        val entry = JSONObject().apply {
            put("reminderId", reminderId); put("title", title); put("category", category)
            put("dueAt", dueAt); put("status", status); put("at", System.currentTimeMillis())
            put("seen", status != "missed")
        }
        val out = JSONArray().put(entry)
        for (i in 0 until minOf(arr.length(), MAX_HISTORY - 1)) out.put(arr.get(i))
        obj.put("history", out)
        persist(ctx)
    }

    fun history(ctx: Context): JSONArray = synchronized(lock) { JSONArray(root(ctx).getJSONArray("history").toString()) }

    fun markHistorySeen(ctx: Context) = synchronized(lock) {
        val arr = root(ctx).getJSONArray("history")
        for (i in 0 until arr.length()) arr.getJSONObject(i).put("seen", true)
        persist(ctx)
    }

    fun clearHistory(ctx: Context) = synchronized(lock) {
        root(ctx).put("history", JSONArray())
        persist(ctx)
    }
}
