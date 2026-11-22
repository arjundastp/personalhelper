package app.remindly.remindly

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Hosts the Flutter UI. FlutterFragmentActivity is required by local_auth (fingerprint / screen lock).
 * All reminder logic is native; Flutter talks to it through the "remindly/native" channel using JSON strings.
 */
class MainActivity : FlutterFragmentActivity() {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private var pendingNotifPermission: MethodChannel.Result? = null

    companion object {
        private const val REQ_PICK_AUDIO = 7001
        private const val REQ_NOTIF = 7002
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "remindly/native")
        channel.setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native_error", e.message, null)
            }
        }
        Store.onChanged = { main.post { runCatching { channel.invokeMethod("changed", null) } } }
        Notifs.ensureChannels(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        consumeIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        consumeIntent(intent)
    }

    private fun consumeIntent(i: Intent?) {
        if (i?.getBooleanExtra("openHistory", false) == true) {
            main.postDelayed({ runCatching { channel.invokeMethod("openHistory", null) } }, 400)
        }
    }

    override fun onDestroy() {
        Store.onChanged = null
        SoundHelper.stopPreview()
        super.onDestroy()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val ctx = applicationContext
        when (call.method) {
            "sync" -> { Scheduler.resync(ctx, ringMissed = true); result.success(null) }
            "getReminders" -> {
                val arr = JSONArray()
                Store.reminders(ctx).forEach { arr.put(it.toJson()) }
                result.success(arr.toString())
            }
            "saveReminder" -> {
                val r = Reminder.fromJson(JSONObject(call.arguments as String))
                // A fresh edit clears any pending snooze of the old version.
                val saved = Scheduler.save(ctx, r.copy(snoozedUntil = null, snoozeAttempt = 0))
                result.success(saved.toJson().toString())
            }
            "deleteReminder" -> { Scheduler.remove(ctx, (call.arguments as Number).toInt()); result.success(null) }
            "setEnabled" -> {
                val id = call.argument<Int>("id")!!
                val enabled = call.argument<Boolean>("enabled")!!
                val r = Store.get(ctx, id)
                if (r == null) result.success(null) else {
                    var updated = r.copy(enabled = enabled, snoozedUntil = null, snoozeAttempt = 0)
                    // Re-enabling a finished one-time reminder whose time has passed: move it to the next day.
                    if (enabled && r.repeat.type == "once" && Recurrence.next(updated, System.currentTimeMillis()) == null) {
                        val now = java.time.LocalDateTime.now()
                        val todayAt = now.toLocalDate().atTime(r.hour, r.minute)
                        val date = if (todayAt.isAfter(now)) now.toLocalDate() else now.toLocalDate().plusDays(1)
                        updated = updated.copy(startDate = date.toString())
                    }
                    result.success(Scheduler.save(ctx, updated).toJson().toString())
                }
            }
            "previewOccurrences" -> {
                val r = Reminder.fromJson(JSONObject(call.argument<String>("reminder")!!))
                val count = call.argument<Int>("count") ?: 3
                result.success(JSONArray(Recurrence.upcoming(r, System.currentTimeMillis(), count)).toString())
            }
            "getSettings" -> result.success(Store.settings(ctx).toString())
            "saveSettings" -> { Store.saveSettings(ctx, JSONObject(call.arguments as String)); result.success(null) }
            "getHistory" -> result.success(Store.history(ctx).toString())
            "markHistorySeen" -> { Store.markHistorySeen(ctx); result.success(null) }
            "clearHistory" -> { Store.clearHistory(ctx); result.success(null) }
            "getSounds" -> {
                val out = JSONObject()
                out.put("app", SoundHelper.bundled())
                out.put("alarm", SoundHelper.system(ctx, "alarm"))
                out.put("ringtone", SoundHelper.system(ctx, "ringtone"))
                out.put("notification", SoundHelper.system(ctx, "notification"))
                result.success(out.toString())
            }
            "previewSound" -> result.success(SoundHelper.preview(ctx, call.arguments as String))
            "stopPreview" -> { SoundHelper.stopPreview(); result.success(null) }
            "pickAudioFile" -> {
                pendingPick?.success(null)
                pendingPick = result
                val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "audio/*"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
                @Suppress("DEPRECATION")
                startActivityForResult(i, REQ_PICK_AUDIO)
            }
            "testAlarm" -> { TestAlarm.schedule(ctx, (call.arguments as? Number)?.toInt() ?: 5); result.success(null) }
            "permissions" -> result.success(permissionStatus().toString())
            "requestPermission" -> requestPermission(call.arguments as String, result)
            "deviceInfo" -> result.success(JSONObject().put("manufacturer", Build.MANUFACTURER).put("sdk", Build.VERSION.SDK_INT).toString())
            else -> result.notImplemented()
        }
    }

    // ---------------- permissions ----------------

    private fun permissionStatus(): JSONObject {
        val nm = getSystemService(NotificationManager::class.java)
        val am = getSystemService(AlarmManager::class.java)
        val pm = getSystemService(PowerManager::class.java)
        return JSONObject().apply {
            put("notifications", nm.areNotificationsEnabled())
            put("fullScreen", if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else true)
            put("exactAlarm", if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true)
            put("battery", pm.isIgnoringBatteryOptimizations(packageName))
            put("dnd", nm.isNotificationPolicyAccessGranted)
            put("overlay", Settings.canDrawOverlays(this@MainActivity))
        }
    }

    private fun requestPermission(name: String, result: MethodChannel.Result) {
        val pkg = Uri.parse("package:$packageName")
        fun open(i: Intent) {
            runCatching { startActivity(i) }.onFailure {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
            }
            result.success(null)
        }
        when (name) {
            "notifications" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                    shouldAskNotificationsInline()
                ) {
                    pendingNotifPermission = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
                } else {
                    open(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                }
            }
            "fullScreen" -> if (Build.VERSION.SDK_INT >= 34) open(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg)) else result.success(null)
            "exactAlarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) open(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, pkg)) else result.success(null)
            "battery" -> {
                @Suppress("BatteryLife")
                open(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg))
            }
            "dnd" -> open(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
            "overlay" -> open(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg))
            "appSettings" -> open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
            else -> result.success(null)
        }
    }

    private var askedNotificationsOnce = false
    private fun shouldAskNotificationsInline(): Boolean {
        // The system dialog can be shown until the user denies twice; after that open settings instead.
        if (!askedNotificationsOnce) { askedNotificationsOnce = true; return true }
        return shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF) { pendingNotifPermission?.success(null); pendingNotifPermission = null }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_AUDIO) return
        val res = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { res.success(null); return }
        runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        var name = "Custom sound"
        runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0).substringBeforeLast('.')
            }
        }
        res.success(JSONObject().put("uri", uri.toString()).put("title", name).put("group", "file").toString())
    }
}
