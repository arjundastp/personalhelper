package app.remindly.remindly

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArraySet

/** Everything the ringing screen needs to know about one alert. */
data class RingRequest(
    val id: Int,
    val title: String,
    val notes: String,
    val category: String,
    val soundUri: String?,
    val vibrate: Boolean,
    val snoozeMinutes: Int,
    val dueAt: Long,
    val missed: Boolean,
    val attempt: Int,
) {
    fun toJson() = JSONObject().apply {
        put("id", id); put("title", title); put("notes", notes); put("category", category)
        put("soundUri", soundUri ?: JSONObject.NULL); put("vibrate", vibrate); put("snoozeMinutes", snoozeMinutes)
        put("dueAt", dueAt); put("missed", missed); put("attempt", attempt)
    }

    companion object {
        fun fromJson(o: JSONObject) = RingRequest(
            o.optInt("id", -1), o.optString("title"), o.optString("notes"), o.optString("category", "custom"),
            o.optStringOrNull("soundUri"), o.optBoolean("vibrate", true), o.optInt("snoozeMinutes", 10),
            o.optLong("dueAt"), o.optBoolean("missed"), o.optInt("attempt"),
        )

        fun from(r: Reminder, settings: JSONObject, dueAt: Long, missed: Boolean, attempt: Int) = RingRequest(
            id = r.id, title = r.title.ifBlank { "Reminder" }, notes = r.notes, category = r.category,
            soundUri = r.soundUri ?: settings.optStringOrNull("defaultSoundUri"),
            vibrate = r.vibrate, snoozeMinutes = r.snoozeMinutes, dueAt = dueAt, missed = missed, attempt = attempt,
        )

        fun test(ctx: Context): RingRequest {
            val s = Store.settings(ctx)
            return RingRequest(
                -1, "Test alert", "This is how your reminders will look and sound.", "custom",
                s.optStringOrNull("defaultSoundUri"), s.optBoolean("vibrate", true), 1,
                System.currentTimeMillis(), false, 0,
            )
        }
    }
}

object Notifs {
    const val CH_ALARM = "remindly_alarm_v1"
    const val CH_MISSED = "remindly_missed_v1"

    fun ensureChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CH_ALARM) == null) {
            nm.createNotificationChannel(NotificationChannel(CH_ALARM, "Reminder alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Full-screen alerts when a reminder is due"
                setSound(null, null) // the alarm service plays the tune itself on the alarm stream
                enableVibration(false)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
        }
        if (nm.getNotificationChannel(CH_MISSED) == null) {
            nm.createNotificationChannel(NotificationChannel(CH_MISSED, "Missed reminders", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Reminders that were not acknowledged"
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
        }
    }

    fun postMissed(ctx: Context, req: RingRequest) {
        ensureChannels(ctx)
        val open = PendingIntent.getActivity(
            ctx, 20_000 + req.id,
            Intent(ctx, MainActivity::class.java).putExtra("openHistory", true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = Notification.Builder(ctx, CH_MISSED)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle("Missed: ${req.title}")
            .setContentText("Was due at ${Fmt.time(ctx, req.dueAt)} · ${Fmt.day(req.dueAt)}")
            .setStyle(Notification.BigTextStyle().bigText(
                listOf("Was due at ${Fmt.time(ctx, req.dueAt)} · ${Fmt.day(req.dueAt)}", req.notes).filter { it.isNotBlank() }.joinToString("\n")
            ))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setColor(Categories.color(req.category))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { ctx.getSystemService(NotificationManager::class.java).notify(30_000 + req.id, n) }
    }
}

/**
 * Foreground service that rings. It plays the tune on the ALARM audio stream (which keeps playing
 * in silent / vibrate mode and, by default, in Do Not Disturb), vibrates, shows the full-screen
 * alert and queues alerts that arrive while another one is ringing.
 */
class AlarmService : Service() {
    companion object {
        const val ACTION_RING = "app.remindly.RING"
        const val ACTION_DISMISS = "app.remindly.DISMISS"
        const val ACTION_SNOOZE = "app.remindly.SNOOZE"
        private const val NOTIF_ID = 4242

        @Volatile var current: RingRequest? = null
            private set
        @Volatile var queuedCount: Int = 0
            private set
        private val listeners = CopyOnWriteArraySet<() -> Unit>()
        fun addListener(l: () -> Unit) = listeners.add(l)
        fun removeListener(l: () -> Unit) = listeners.remove(l)

        fun ring(ctx: Context, req: RingRequest) {
            val i = Intent(ctx, AlarmService::class.java).setAction(ACTION_RING).putExtra("req", req.toJson().toString())
            ctx.startForegroundService(i)
        }

        fun send(ctx: Context, action: String) {
            if (current == null) return
            runCatching { ctx.startService(Intent(ctx, AlarmService::class.java).setAction(action)) }
        }
    }

    private val queue = ArrayDeque<RingRequest>()
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var savedAlarmVolume: Int? = null
    private var savedInterruptionFilter: Int? = null
    private var volumeStep = 0

    private val timeout = Runnable { onTimeout() }
    private val rampUp = object : Runnable {
        override fun run() {
            val p = player ?: return
            volumeStep++
            val v = (0.15f + volumeStep * 0.05f).coerceAtMost(1f)
            runCatching { p.setVolume(v, v) }
            if (v < 1f) handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RING -> {
                val req = runCatching { RingRequest.fromJson(JSONObject(intent.getStringExtra("req")!!)) }.getOrNull()
                if (req == null) { stopIfIdle(); return START_NOT_STICKY }
                if (current == null) startRinging(req) else {
                    if (queue.none { it.id == req.id && req.id >= 0 } && current?.id != req.id) queue.addLast(req)
                    goForeground(current!!) // every startForegroundService needs a startForeground
                    notifyListeners()
                }
            }
            ACTION_DISMISS -> finishCurrent("done")
            ACTION_SNOOZE -> finishCurrent("snoozed")
            else -> stopIfIdle()
        }
        return START_NOT_STICKY
    }

    private fun goForeground(req: RingRequest) {
        val n = buildNotification(req)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun startRinging(req: RingRequest) {
        current = req
        Notifs.ensureChannels(this)
        goForeground(req)
        val settings = Store.settings(this)
        val ringMinutes = settings.optInt("ringMinutes", 2).coerceIn(1, 30)

        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "remindly:ring").apply { setReferenceCounted(false) }
        }
        wakeLock?.acquire((ringMinutes + 1) * 60_000L)

        prepareAudioPolicy(settings)
        startSound(req.soundUri, settings.optBoolean("gradualVolume", true))
        if (req.vibrate) startVibration()

        // With "display over other apps" we can show the alert even while the phone is in use;
        // otherwise Android shows the full-screen intent when locked and a heads-up when unlocked.
        if (Settings.canDrawOverlays(this)) {
            runCatching {
                startActivity(Intent(this, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION))
            }
        }
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, ringMinutes * 60_000L)
        notifyListeners()
    }

    private fun onTimeout() {
        val req = current ?: return
        val autoRepeat = Store.settings(this).optInt("autoRepeat", 3)
        if (req.id >= 0) {
            if (req.attempt < autoRepeat) {
                Scheduler.snooze(this, req.id, req.snoozeMinutes, auto = true, attempt = req.attempt + 1)
                Store.log(this, req.id, req.title, req.category, req.dueAt, "auto_snoozed")
            } else {
                Store.log(this, req.id, req.title, req.category, req.dueAt, "missed")
                Notifs.postMissed(this, req)
            }
        }
        advance()
    }

    private fun finishCurrent(status: String) {
        val req = current ?: run { stopIfIdle(); return }
        if (req.id >= 0) {
            if (status == "snoozed") Scheduler.snooze(this, req.id, req.snoozeMinutes, auto = false, attempt = 0)
            Store.log(this, req.id, req.title, req.category, req.dueAt, status)
        }
        advance()
    }

    private fun advance() {
        stopAlerting()
        current = null
        val next = queue.removeFirstOrNull()
        if (next != null) startRinging(next) else {
            notifyListeners()
            stopIfIdle()
        }
    }

    private fun stopIfIdle() {
        if (current != null) return
        stopForeground(STOP_FOREGROUND_REMOVE)
        wakeLock?.let { if (it.isHeld) it.release() }
        stopSelf()
    }

    private fun notifyListeners() = handler.post {
        queuedCount = queue.size
        listeners.forEach { runCatching { it() } }
    }

    // ---------------- audio ----------------

    private fun prepareAudioPolicy(settings: JSONObject) {
        val am = getSystemService(AudioManager::class.java)
        if (settings.optBoolean("ensureVolume", true) && savedAlarmVolume == null) {
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val want = (max * settings.optInt("minVolume", 70).coerceIn(10, 100) / 100.0).toInt().coerceAtLeast(1)
            val cur = am.getStreamVolume(AudioManager.STREAM_ALARM)
            if (cur < want) runCatching {
                am.setStreamVolume(AudioManager.STREAM_ALARM, want, 0)
                savedAlarmVolume = cur
            }
        }
        // "Total silence" DND blocks even alarms. If the user granted DND access, relax it to
        // "alarms only" while ringing and restore it afterwards.
        val nm = getSystemService(NotificationManager::class.java)
        if (settings.optBoolean("overrideDnd", true) && nm.isNotificationPolicyAccessGranted && savedInterruptionFilter == null) {
            val f = nm.currentInterruptionFilter
            if (f == NotificationManager.INTERRUPTION_FILTER_NONE) runCatching {
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
                savedInterruptionFilter = f
            }
        }
    }

    private fun startSound(uriString: String?, gradual: Boolean) {
        val candidates = listOfNotNull(
            uriString?.let { SoundHelper.resolve(this, it) },
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM),
            Settings.System.DEFAULT_ALARM_ALERT_URI,
            SoundHelper.resolve(this, SoundHelper.bundledUri("gentle_chime")),
        )
        for (uri in candidates) {
            val p = MediaPlayer()
            try {
                p.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                p.setDataSource(this, uri)
                p.isLooping = true
                p.prepare()
                volumeStep = 0
                if (gradual) p.setVolume(0.15f, 0.15f)
                p.start()
                player = p
                if (gradual) handler.postDelayed(rampUp, 1000)
                return
            } catch (e: Exception) {
                runCatching { p.release() }
            }
        }
    }

    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) getSystemService(VibratorManager::class.java).defaultVibrator
        else @Suppress("DEPRECATION") getSystemService(Vibrator::class.java)

    private fun startVibration() {
        val pattern = longArrayOf(0, 700, 500, 700, 1200)
        val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
        @Suppress("DEPRECATION")
        runCatching { vibrator().vibrate(VibrationEffect.createWaveform(pattern, 0), attrs) }
    }

    private fun stopAlerting() {
        handler.removeCallbacks(timeout)
        handler.removeCallbacks(rampUp)
        player?.let { runCatching { it.stop() }; runCatching { it.release() } }
        player = null
        runCatching { vibrator().cancel() }
        val am = getSystemService(AudioManager::class.java)
        savedAlarmVolume?.let { runCatching { am.setStreamVolume(AudioManager.STREAM_ALARM, it, 0) } }
        savedAlarmVolume = null
        val nm = getSystemService(NotificationManager::class.java)
        savedInterruptionFilter?.let { runCatching { nm.setInterruptionFilter(it) } }
        savedInterruptionFilter = null
    }

    override fun onDestroy() {
        stopAlerting()
        current = null
        notifyListeners()
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    // ---------------- notification ----------------

    private fun buildNotification(req: RingRequest): Notification {
        val full = PendingIntent.getActivity(
            this, 1,
            Intent(this, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun action(a: String, code: Int) = PendingIntent.getService(
            this, code, Intent(this, AlarmService::class.java).setAction(a), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val text = if (req.missed) "Missed while your phone was off · was due ${Fmt.time(this, req.dueAt)}"
        else listOf("Due ${Fmt.time(this, req.dueAt)}", req.notes).filter { it.isNotBlank() }.joinToString(" · ")
        return Notification.Builder(this, Notifs.CH_ALARM)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle("${Categories.emoji(req.category)}  ${req.title}")
            .setContentText(text)
            .setCategory(Notification.CATEGORY_ALARM)
            .setColor(Categories.color(req.category))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setShowWhen(true)
            .setWhen(req.dueAt)
            .setFullScreenIntent(full, true)
            .setContentIntent(full)
            .addAction(Notification.Action.Builder(null, "Snooze ${req.snoozeMinutes} min", action(ACTION_SNOOZE, 2)).build())
            .addAction(Notification.Action.Builder(null, "Dismiss", action(ACTION_DISMISS, 3)).build())
            .build()
    }
}

object Categories {
    fun emoji(key: String) = when (key) {
        "medicine" -> "💊"; "water" -> "💧"; "vehicle" -> "🚗"; "bills" -> "🧾"; "birthday" -> "🎂"
        "doctor" -> "🩺"; "exercise" -> "🏃"; "meeting" -> "📅"; "plants" -> "🪴"; "pets" -> "🐾"
        else -> "🔔"
    }

    fun color(key: String): Int = when (key) {
        "medicine" -> 0xFFE5484D; "water" -> 0xFF0090FF; "vehicle" -> 0xFF8E4EC6; "bills" -> 0xFFF76B15
        "birthday" -> 0xFFD6409F; "doctor" -> 0xFF12A594; "exercise" -> 0xFF30A46C; "meeting" -> 0xFF3E63DD
        "plants" -> 0xFF46A758; "pets" -> 0xFFAD7F58
        else -> 0xFF0D74CE
    }.toInt()
}

object Fmt {
    fun time(ctx: Context, millis: Long): String = android.text.format.DateFormat.getTimeFormat(ctx).format(java.util.Date(millis))
    fun day(millis: Long): String {
        val d = java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        val today = java.time.LocalDate.now()
        return when (d) {
            today -> "Today"
            today.minusDays(1) -> "Yesterday"
            else -> d.format(java.time.format.DateTimeFormatter.ofPattern("EEE, d MMM"))
        }
    }
}
