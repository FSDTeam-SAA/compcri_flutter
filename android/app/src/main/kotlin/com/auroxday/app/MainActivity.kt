package com.auroxday.app

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** The data of a banner tapped before Flutter asked for it (cold start). */
    private var pendingOpen: HashMap<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
        pendingOpen = openedData(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = openedData(intent) ?: return
        // Running app: hand the tap straight to Flutter.
        val current = channel
        if (current != null) current.invokeMethod("opened", data) else pendingOpen = data
    }

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    private fun openedData(intent: Intent?): HashMap<String, String>? =
        intent?.getSerializableExtra(OPEN_EXTRA) as? HashMap<String, String>

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.auroxday.app/notifications")
        channel!!.setMethodCallHandler { call, result ->
                val manager = getSystemService(NotificationManager::class.java)
                when (call.method) {
                    "notificationsEnabled" -> result.success(
                        (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || manager.areNotificationsEnabled()) &&
                        (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            manager.getNotificationChannel(if (call.argument<Boolean>("alarm") == true) "aurox_alarms" else "aurox_reminders_silent")?.importance != NotificationManager.IMPORTANCE_NONE)
                    )
                    "openSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "takeOpened" -> {
                        result.success(pendingOpen)
                        pendingOpen = null
                    }
                    "show" -> {
                        createNotificationChannels()
                        val alarm = call.argument<Boolean>("alarm") == true
                        val id = call.argument<String>("id").orEmpty().hashCode()
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Notification.Builder(this, if (alarm) "aurox_alarms" else "aurox_reminders_silent")
                        } else {
                            @Suppress("DEPRECATION")
                            Notification.Builder(this)
                        }
                        // The tap carries the notification's data, so the app
                        // can open the event it is about.
                        val data = HashMap<String, String>()
                        call.argument<Map<String, Any?>>("data")?.forEach { (key, value) ->
                            if (value != null) data[key] = value.toString()
                        }
                        val open = PendingIntent.getActivity(this, id,
                            Intent(this, MainActivity::class.java)
                                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                .putExtra(OPEN_EXTRA, data),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        builder.setSmallIcon(R.drawable.ic_notification)
                            .setContentTitle(call.argument<String>("title"))
                            .setContentText(call.argument<String>("body"))
                            .setStyle(Notification.BigTextStyle().bigText(call.argument<String>("body")))
                            .setContentIntent(open).setAutoCancel(true)
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            @Suppress("DEPRECATION")
                            builder.setPriority(Notification.PRIORITY_HIGH)
                            if (alarm) builder.setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
                        }
                        try {
                            manager.notify(id, builder.build())
                            result.success(null)
                        } catch (_: SecurityException) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Declare the channels before Firebase needs them. The silent reminder
     * channel shows a banner without sound; the alarm channel also rings.
     * Channel settings belong here because
     * importance is fixed when the channel is created and Android will not let
     * it be raised afterwards.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        manager.createNotificationChannel(
            NotificationChannel(
                "aurox_reminders_silent",
                "Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Event reminders without alarm sound"
                setSound(null, null)
                enableVibration(false)
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                "aurox_alarms",
                "Urgent reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders that should interrupt you"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 300, 500, 300, 500)
                setBypassDnd(true)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )
    }

    companion object {
        private const val OPEN_EXTRA = "com.auroxday.app.notification"
    }
}
