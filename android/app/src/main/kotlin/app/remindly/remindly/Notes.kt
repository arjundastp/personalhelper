package app.remindly.remindly

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Daily Sprint notes, kept apart from the main data file: an index (titles, text, dates) and one
 * file of handwriting per note, so large handwriting never slows down the rest of the app.
 */
object Notes {
    private const val INDEX = "notes.json"
    private const val INK_DIR = "notes_ink"
    private val lock = Any()

    private fun indexFile(ctx: Context) = File(ctx.filesDir, INDEX)
    private fun inkFile(ctx: Context, id: Int) = File(File(ctx.filesDir, INK_DIR).apply { mkdirs() }, "$id.json")

    private fun write(f: File, text: String) {
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(f)) { f.writeText(text); tmp.delete() }
    }

    fun index(ctx: Context): String = synchronized(lock) { indexFile(ctx).takeIf { it.exists() }?.readText() ?: "[]" }

    fun saveIndex(ctx: Context, json: String) = synchronized(lock) { write(indexFile(ctx), json) }

    fun ink(ctx: Context, id: Int): String? = synchronized(lock) { inkFile(ctx, id).takeIf { it.exists() }?.readText() }

    fun saveInk(ctx: Context, id: Int, json: String) = synchronized(lock) { write(inkFile(ctx, id), json) }

    fun deleteInk(ctx: Context, id: Int) = synchronized(lock) { inkFile(ctx, id).delete(); Unit }

    /** For backups: {"index": [...], "ink": {"<id>": [...]}}. */
    fun export(ctx: Context): JSONObject = synchronized(lock) {
        val idx = runCatching { JSONArray(index(ctx)) }.getOrDefault(JSONArray())
        val ink = JSONObject()
        for (i in 0 until idx.length()) {
            val id = idx.getJSONObject(i).optInt("id")
            ink(ctx, id)?.let { text -> runCatching { ink.put(id.toString(), JSONArray(text)) } }
        }
        JSONObject().put("index", idx).put("ink", ink)
    }

    /** Restores notes from a backup, replacing the current ones. */
    fun import(ctx: Context, data: JSONObject) = synchronized(lock) {
        File(ctx.filesDir, INK_DIR).deleteRecursively()
        val idx = data.optJSONArray("index") ?: JSONArray()
        write(indexFile(ctx), idx.toString())
        val ink = data.optJSONObject("ink") ?: return@synchronized
        ink.keys().forEach { k -> k.toIntOrNull()?.let { id -> write(inkFile(ctx, id), ink.getJSONArray(k).toString()) } }
    }
}
