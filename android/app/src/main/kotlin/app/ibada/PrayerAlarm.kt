package app.ibada

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

internal object PrayerAlarm {
    const val BRIDGE = "app.ibada/alarms"
    private const val CHANNEL = "prayer_sound_v1"
    private const val ALARM_CHANNEL = "prayer_alarm_v1"
    private const val ACTION_FIRE = "app.ibada.FIRE_PRAYER_ALARM"
    private const val ACTION_TEST = "app.ibada.TEST_PRAYER_ALARM"
    private const val ACTION_STOP = "app.ibada.STOP_PRAYER_ALARM"
    private const val NEXT_REQUEST = 1400
    private const val TEST_REQUEST = 1401
    private const val REFRESH_JOB = 1402
    private const val ALERT_TIMEOUT = 90000L
    const val NOTIFICATION_ID = "notificationId"
    const val TITLE = "title"
    const val TIME = "time"
    const val SHOWN_AT = "shownAt"

    private val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun store(context: Context) =
        context.createDeviceProtectedStorageContext().getSharedPreferences("prayer-alarms", Context.MODE_PRIVATE)

    fun revision(context: Context) = store(context).getLong("revision", 0)

    fun exact(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    fun fullScreen(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent()
    }

    fun notificationAllowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && (
            Build.VERSION.SDK_INT < 33 ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            )
    }

    fun channelSettings(context: Context): String {
        channels(context)
        return if (store(context).getBoolean("fullScreen", true)) ALARM_CHANNEL else CHANNEL
    }

    fun status(context: Context): Map<String, Boolean> {
        val manager = context.getSystemService(NotificationManager::class.java)
        val active = manager.getNotificationChannel(channelSettings(context))
        return mapOf(
            "notifications" to (notificationAllowed(context) && active.importance != NotificationManager.IMPORTANCE_NONE),
            "exact" to exact(context),
            "fullScreen" to (fullScreen(context) &&
                (active.id != ALARM_CHANNEL || active.importance >= NotificationManager.IMPORTANCE_HIGH)),
        )
    }

    fun replace(context: Context, args: Map<*, *>) {
        val events = args["events"] as? List<*> ?: error("Missing prayer alarm plan")
        val full = args["fullScreen"] as? Boolean ?: false
        val plan = JSONArray()
        events.forEach { row ->
            val event = row as Map<*, *>
            plan.put(JSONObject().apply {
                put(TIME, (event["time"] as Number).toLong())
                put(TITLE, event["label"] as String)
            })
        }
        check(store(context).edit()
            .putString("plan", plan.toString())
            .putBoolean("fullScreen", full)
            .putLong("revision", revision(context) + 1)
            .commit())
        rearm(context)
        val jobs = context.getSystemService(JobScheduler::class.java)
        if (plan.length() == 0) {
            jobs.cancel(REFRESH_JOB)
        } else if (jobs.getPendingJob(REFRESH_JOB) == null) {
            jobs.schedule(
                JobInfo.Builder(REFRESH_JOB, ComponentName(context, PrayerRefreshJob::class.java))
                    .setPeriodic(24 * 60 * 60 * 1000L)
                    .setPersisted(true)
                    .build(),
            )
        }
    }

    private fun plan(context: Context) =
        JSONArray(store(context).getString("plan", "[]") ?: "[]")

    private fun pending(context: Context, action: String, code: Int, time: Long): PendingIntent =
        PendingIntent.getBroadcast(context, code, Intent(context, PrayerAlarmReceiver::class.java)
            .setAction(action).putExtra(TIME, time), pendingFlags)

    fun rearm(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val events = plan(context)
        val now = System.currentTimeMillis()
        val armed = store(context).getLong("armedTime", 0)
        if (now - armed in 0..120_000L) deliver(context, armed, events)
        for (index in 0 until events.length()) {
            val time = events.getJSONObject(index).getLong(TIME)
            if (time > now) {
                schedule(context, time, pending(context, ACTION_FIRE, NEXT_REQUEST, time))
                store(context).edit().putLong("armedTime", time).apply()
                return
            }
        }
        alarms.cancel(pending(context, ACTION_FIRE, NEXT_REQUEST, 0))
        store(context).edit().remove("armedTime").apply()
    }

    fun test(context: Context, fullScreen: Boolean) {
        check(notificationAllowed(context)) { "Notifications are disabled" }
        check(exact(context)) { "Exact alarm access is disabled" }
        val time = System.currentTimeMillis() + 15000L
        val request = PendingIntent.getBroadcast(
            context, TEST_REQUEST,
            Intent(context, PrayerAlarmReceiver::class.java).setAction(ACTION_TEST)
                .putExtra(TIME, time).putExtra("fullScreen", fullScreen),
            pendingFlags,
        )
        schedule(context, time, request)
    }

    private fun schedule(context: Context, time: Long, operation: PendingIntent) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        if (exact(context)) {
            try {
                val show = PendingIntent.getActivity(context, 0, Intent(context, HomeActivity::class.java), pendingFlags)
                alarms.setAlarmClock(AlarmManager.AlarmClockInfo(time, show), operation)
                return
            } catch (_: SecurityException) {
                // Exact-alarm access can be revoked between the check and the call.
            }
        }
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, operation)
    }

    fun receive(context: Context, intent: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val time = intent.getLongExtra(TIME, 0)
        val recent = System.currentTimeMillis() - time in 0..3_600_000L
        when (intent.action) {
            ACTION_STOP -> manager.cancel(intent.getIntExtra(NOTIFICATION_ID, 0))
            ACTION_TEST -> {
                if (recent) notify(context, "تنبيه تجريبي", time, intent.getBooleanExtra("fullScreen", true))
            }
            ACTION_FIRE -> {
                if (recent) deliver(context, time, plan(context))
                rearm(context)
            }
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> rearm(context)
        }
    }

    private fun deliver(context: Context, time: Long, events: JSONArray) {
        val saved = store(context)
        if (saved.getLong("lastDelivered", 0) == time) return
        val labels = (0 until events.length()).asSequence().map(events::getJSONObject)
            .filter { it.getLong(TIME) == time }.map { it.getString(TITLE) }.distinct().toList()
        if (labels.isEmpty()) return
        saved.edit().putLong("lastDelivered", time).apply()
        notify(context, "حان موعد ${labels.joinToString(" و")}", time, saved.getBoolean("fullScreen", true))
    }

    private fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val sound = Uri.parse("android.resource://${context.packageName}/raw/prayer_chime")
        for ((id, name, usage) in listOf(
            Triple(CHANNEL, "إشعارات الصلاة", AudioAttributes.USAGE_NOTIFICATION_EVENT),
            Triple(ALARM_CHANNEL, "منبّه الصلاة", AudioAttributes.USAGE_ALARM),
        )) {
            manager.createNotificationChannel(
                NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    enableVibration(true)
                    setSound(sound, AudioAttributes.Builder()
                        .setUsage(usage).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                },
            )
        }
    }

    private fun notify(context: Context, title: String, time: Long, wantsFullScreen: Boolean) {
        if (!notificationAllowed(context)) return
        channels(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = time.hashCode()
        val channel = if (wantsFullScreen) ALARM_CHANNEL else CHANNEL
        val alarm = Intent(context, PrayerAlarmActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(TITLE, title).putExtra(SHOWN_AT, System.currentTimeMillis()).putExtra(NOTIFICATION_ID, id)
        val full = PendingIntent.getActivity(context, id, alarm, pendingFlags)
        val open = if (wantsFullScreen) full else PendingIntent.getActivity(
            context, id, Intent(context, HomeActivity::class.java), pendingFlags,
        )
        val stop = PendingIntent.getBroadcast(context, id, Intent(context, PrayerAlarmReceiver::class.java)
            .setAction(ACTION_STOP).putExtra(NOTIFICATION_ID, id), pendingFlags)
        val builder = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_prayer_notification)
            .setContentTitle(title)
            .setContentText("عبادة")
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setTimeoutAfter(ALERT_TIMEOUT)
            .setWhen(time)
            .setShowWhen(true)
            .setAutoCancel(!wantsFullScreen)
            .addAction(Notification.Action.Builder(null, "إيقاف", stop).build())
        val immersive = wantsFullScreen && fullScreen(context) &&
            manager.getNotificationChannel(channel).importance >= NotificationManager.IMPORTANCE_HIGH
        if (immersive) builder.setFullScreenIntent(full, true)
        val notification = builder.build()
        if (immersive) notification.flags = notification.flags or Notification.FLAG_INSISTENT
        manager.notify(id, notification)
    }
}

class PrayerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = PrayerAlarm.receive(context, intent)
}

class PrayerRefreshJob : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var active: JobParameters? = null
    private val timeout = Runnable { finishJob(true) }

    override fun onStartJob(params: JobParameters): Boolean {
        active = params
        val version = PrayerAlarm.revision(this)
        handler.post {
            if (active !== params) return@post
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationCompleteAsync(applicationContext, null, handler) {
                    if (active !== params) return@ensureInitializationCompleteAsync
                    try {
                        val worker = FlutterEngine(applicationContext)
                        engine = worker
                        MethodChannel(worker.dartExecutor.binaryMessenger, PrayerAlarm.BRIDGE)
                            .setMethodCallHandler { call, reply ->
                                when (call.method) {
                                    "replace" -> try {
                                        if (version == PrayerAlarm.revision(this)) {
                                            PrayerAlarm.replace(this, call.arguments as Map<*, *>)
                                        }
                                        reply.success(null)
                                    } catch (error: Exception) {
                                        reply.error("ALARM_REFRESH", error.message, null)
                                    }
                                    "complete" -> {
                                        reply.success(null)
                                        handler.post { finishJob(call.arguments != true) }
                                    }
                                    else -> reply.notImplemented()
                                }
                            }
                        worker.dartExecutor.executeDartEntrypoint(
                            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "refreshPrayerAlarms"),
                        )
                    } catch (_: Exception) {
                        finishJob(true)
                    }
                }
            } catch (_: Exception) {
                finishJob(true)
            }
        }
        handler.postDelayed(timeout, 45000)
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        active = null
        destroyEngine()
        return true
    }

    private fun finishJob(retry: Boolean) {
        val params = active ?: return
        active = null
        destroyEngine()
        jobFinished(params, retry)
    }

    private fun destroyEngine() {
        handler.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
    }
}

class PrayerAlarmActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val close = Runnable { finish() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    private fun render() {
        handler.removeCallbacks(close)
        val remaining = 90000L - (System.currentTimeMillis() - intent.getLongExtra(PrayerAlarm.SHOWN_AT, 0))
        if (remaining <= 0) {
            dismiss()
            return
        }
        handler.postDelayed(close, remaining.coerceAtMost(90000))
        val dp = resources.displayMetrics.density
        fun px(value: Int) = (value * dp).toInt()
        val pine = Color.rgb(20, 44, 37)
        val cream = Color.rgb(252, 245, 227)
        val amber = Color.rgb(244, 207, 144)
        val fontPath = "flutter_assets/assets/fonts"
        val regularFont = Typeface.createFromAsset(assets, "$fontPath/thmanyahsans-Regular.otf")
        val boldFont = Typeface.createFromAsset(assets, "$fontPath/thmanyahsans-Bold.otf")
        val stack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutDirection = LinearLayout.LAYOUT_DIRECTION_RTL
            setPadding(px(26), px(60), px(26), px(60))
            setBackgroundColor(pine)
        }
        stack.addView(TextView(this).apply {
            text = "عبادة"
            textSize = 18f
            typeface = regularFont
            setTextColor(amber)
            gravity = Gravity.CENTER
        })
        stack.addView(TextView(this).apply {
            text = intent.getStringExtra(PrayerAlarm.TITLE) ?: "تنبيه الصلاة"
            textSize = 33f
            gravity = Gravity.CENTER
            setTextColor(cream)
            typeface = boldFont
            setPadding(0, px(22), 0, px(50))
        })
        stack.addView(Button(this).apply {
            text = "إيقاف التنبيه"
            textSize = 17f
            typeface = regularFont
            setTextColor(pine)
            minHeight = px(56)
            backgroundTintList = ColorStateList.valueOf(amber)
            setOnClickListener { dismiss() }
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        setContentView(ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(pine)
            addView(stack)
        })
    }

    private fun dismiss() {
        getSystemService(NotificationManager::class.java)
            .cancel(intent.getIntExtra(PrayerAlarm.NOTIFICATION_ID, 0))
        finish()
    }

    @Deprecated("Legacy back dispatch")
    override fun onBackPressed() = dismiss()

    override fun onDestroy() {
        handler.removeCallbacks(close)
        super.onDestroy()
    }
}
