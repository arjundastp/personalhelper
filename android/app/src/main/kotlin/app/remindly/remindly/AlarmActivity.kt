package app.remindly.remindly

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** The big full-screen alert. Works over the lock screen and turns the screen on. */
class AlarmActivity : Activity() {
    private val listener: () -> Unit = { render() }
    private var pulse: AnimatorSet? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_alarm)

        findViewById<Button>(R.id.dismiss).setOnClickListener {
            AlarmService.send(this, AlarmService.ACTION_DISMISS)
        }
        findViewById<Button>(R.id.snooze).setOnClickListener {
            AlarmService.send(this, AlarmService.ACTION_SNOOZE)
        }
        startPulse()
    }

    override fun onStart() {
        super.onStart()
        AlarmService.addListener(listener)
        render()
    }

    override fun onStop() {
        AlarmService.removeListener(listener)
        super.onStop()
    }

    override fun onDestroy() {
        pulse?.cancel()
        super.onDestroy()
    }

    @Deprecated("Back must not silently dismiss an alert; the user chooses Dismiss or Snooze.")
    override fun onBackPressed() { /* intentionally ignored */ }

    private fun render() {
        val req = AlarmService.current
        if (req == null) { finishAndRemoveTask(); return }
        val color = Categories.color(req.category)
        findViewById<View>(R.id.root).background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(darken(color, 0.55f), color, darken(color, 0.75f)),
        )
        window.statusBarColor = Color.TRANSPARENT

        findViewById<TextView>(R.id.status).text = (if (req.soundOn) "" else "🔕  ") + when {
            req.missed -> "Missed while phone was off · due ${Fmt.time(this, req.dueAt)}"
            req.attempt > 0 -> "Reminder again · due ${Fmt.time(this, req.dueAt)}"
            else -> "Reminder · ${Fmt.time(this, req.dueAt)}"
        }
        findViewById<TextView>(R.id.date).text = LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, d MMMM"))
        findViewById<TextView>(R.id.icon).text = Categories.emoji(req.category)
        findViewById<TextView>(R.id.title).text = req.title
        findViewById<TextView>(R.id.notes).apply {
            text = req.notes
            visibility = if (req.notes.isBlank()) View.GONE else View.VISIBLE
        }
        findViewById<TextView>(R.id.queue).apply {
            val more = AlarmService.queuedCount
            text = if (more > 0) "+$more more reminder${if (more > 1) "s" else ""} waiting" else ""
            visibility = if (more > 0) View.VISIBLE else View.GONE
        }

        findViewById<Button>(R.id.dismiss).apply {
            text = if (req.missed) "Got it" else "Done  ✓"
            setTextColor(darken(color, 0.8f))
        }
        findViewById<Button>(R.id.snooze).apply {
            text = "Remind me in ${req.snoozeMinutes} min"
            visibility = if (req.id < 0) View.GONE else View.VISIBLE
        }
    }

    private fun startPulse() {
        val v = findViewById<View>(R.id.pulse)
        val sx = ObjectAnimator.ofFloat(v, View.SCALE_X, 0.75f, 1.1f)
        val sy = ObjectAnimator.ofFloat(v, View.SCALE_Y, 0.75f, 1.1f)
        val a = ObjectAnimator.ofFloat(v, View.ALPHA, 1f, 0.2f)
        listOf(sx, sy, a).forEach { it.repeatCount = ValueAnimator.INFINITE; it.repeatMode = ValueAnimator.REVERSE; it.duration = 900 }
        pulse = AnimatorSet().apply { playTogether(sx, sy, a); start() }
    }

    private fun darken(c: Int, f: Float) = Color.rgb(
        (Color.red(c) * f).toInt(), (Color.green(c) * f).toInt(), (Color.blue(c) * f).toInt()
    )
}
