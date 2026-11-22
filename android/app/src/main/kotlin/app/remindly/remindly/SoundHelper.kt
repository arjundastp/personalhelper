package app.remindly.remindly

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject

object SoundHelper {
    private const val SCHEME = "remindly-tune://"

    /** Tunes shipped inside the app (res/raw/tune_<key>.ogg). */
    val BUNDLED = linkedMapOf(
        "gentle_chime" to "Gentle Chime",
        "morning_marimba" to "Morning Marimba",
        "soft_bells" to "Soft Bells",
        "ding_dong" to "Ding Dong",
        "water_drop" to "Water Drop",
        "lullaby" to "Lullaby",
        "rising_alert" to "Rising Alert",
        "classic_beep" to "Classic Beep",
        "digital_alarm" to "Digital Alarm",
        "heartbeat_pulse" to "Heartbeat Pulse",
    )

    fun bundledUri(key: String) = "$SCHEME$key"

    fun resolve(ctx: Context, value: String): Uri? {
        if (value.startsWith(SCHEME)) {
            val key = value.removePrefix(SCHEME)
            val id = ctx.resources.getIdentifier("tune_$key", "raw", ctx.packageName)
            if (id == 0) return null
            return Uri.parse("android.resource://${ctx.packageName}/$id")
        }
        return runCatching { Uri.parse(value) }.getOrNull()
    }

    fun bundled(): JSONArray = JSONArray().apply {
        BUNDLED.forEach { (k, v) -> put(JSONObject().put("uri", bundledUri(k)).put("title", v).put("group", "app")) }
    }

    /** group: alarm | ringtone | notification */
    fun system(ctx: Context, group: String): JSONArray {
        val out = JSONArray()
        val type = when (group) {
            "ringtone" -> RingtoneManager.TYPE_RINGTONE
            "notification" -> RingtoneManager.TYPE_NOTIFICATION
            else -> RingtoneManager.TYPE_ALARM
        }
        runCatching {
            val rm = RingtoneManager(ctx)
            rm.setType(type)
            val c = rm.cursor
            val seen = HashSet<String>()
            while (c.moveToNext()) {
                val title = c.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: continue
                val uri = rm.getRingtoneUri(c.position)?.toString() ?: continue
                if (seen.add(uri)) out.put(JSONObject().put("uri", uri).put("title", title).put("group", group))
            }
        }
        return out
    }

    // ---------------- preview ----------------

    private var preview: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopPreview() }

    fun preview(ctx: Context, value: String): Boolean {
        stopPreview()
        val uri = resolve(ctx, value) ?: return false
        val p = MediaPlayer()
        return try {
            p.setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            )
            p.setDataSource(ctx, uri)
            p.isLooping = true
            p.prepare()
            p.start()
            preview = p
            handler.postDelayed(autoStop, 12_000)
            true
        } catch (e: Exception) {
            runCatching { p.release() }
            false
        }
    }

    fun stopPreview() {
        handler.removeCallbacks(autoStop)
        preview?.let { runCatching { it.stop() }; runCatching { it.release() } }
        preview = null
    }
}
