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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.auroxday.app/notifications")
            .setMethodCallHandler { call, result ->
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
                        val open = PendingIntent.getActivity(this, id,
                            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
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
}
