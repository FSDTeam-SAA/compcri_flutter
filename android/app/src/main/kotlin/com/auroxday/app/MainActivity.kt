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
                            manager.getNotificationChannel(if (call.argument<Boolean>("alarm") == true) "aurox_alarms" else REMINDER_CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
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
                        val reminder = call.argument<String>("category") == "REMINDER"
                        val id = call.argument<String>("id").orEmpty().hashCode()
                        val channelId = when {
                            alarm -> "aurox_alarms"
                            reminder -> REMINDER_CHANNEL
                            else -> "aurox_reminders_silent"
                        }
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Notification.Builder(this, channelId)
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
                            if (alarm) {
                                builder.setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
                            } else if (reminder) {
                                // No channels before Android 8: the sound goes on the notification.
                                builder.setDefaults(Notification.DEFAULT_VIBRATE)
                                builder.setSound(android.net.Uri.parse("android.resource://$packageName/${R.raw.aurox_reminder}"))
                            }
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
     * Declare the channels before Firebase needs them. Reminders make the
     * phone's notification sound; alarm-style reminders ring like an alarm and
     * break through Do Not Disturb; everything else shows quietly. The quiet
     * channel keeps its old id because a channel's sound cannot be changed
     * once it exists, so reminders moved to a new one instead.
     * Channel settings belong here because
     * importance is fixed when the channel is created and Android will not let
     * it be raised afterwards.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        // The first sound channel used the phone's default sound, which some
        // phones do not have; reminders now carry the app's own.
        manager.deleteNotificationChannel("aurox_reminders")
        manager.createNotificationChannel(
            NotificationChannel(
                REMINDER_CHANNEL,
                "Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Event reminders"
                enableVibration(true)
                setSound(
                    android.net.Uri.parse("android.resource://$packageName/${R.raw.aurox_reminder}"),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )

        manager.createNotificationChannel(
            NotificationChannel(
                "aurox_reminders_silent",
                "Updates",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Invitations and other updates, without sound"
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

        /**
         * Reminders play the app's own sound, the same on every phone.
         * To change it: replace res/raw/aurox_reminder.wav and
         * ios/Runner/aurox_reminder.caf, then raise this version (Android
         * keeps a channel's sound for good) and the server's channelId in
         * services/notification.service.js to match.
         */
        const val REMINDER_CHANNEL = "aurox_reminders_v2"
    }
}
