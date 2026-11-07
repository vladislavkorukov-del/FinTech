package com.finora.fintech

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Finora outside the app screen (1.27): home-screen widgets, the Quick
 * Settings tile and the shade controls open the app with an action.
 */
class FinoraBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val EXTRA_ACTION = "finora_action"
        const val SHADE_CHANNEL = "finora_shade"
        const val SHADE_ID = 7301
        const val PREFS = "finora_widgets"

        /** Opens the app with [action]: voice, expense, income, scan, payments. */
        fun launch(context: Context, action: String, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                putExtra(EXTRA_ACTION, action)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    private val channel = MethodChannel(messenger, "finora/system")
    private var pendingAction: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                "updateWidgets" -> {
                    saveWidgets(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    result.success(true)
                }
                "shade" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on) {
                        showShade(
                            call.argument<String>("title") ?: "Финора",
                            call.argument<String>("text") ?: "",
                        )
                    } else {
                        hideShade()
                    }
                    result.success(true)
                }
                "ping" -> result.success(true)
                "vibrate" -> {
                    // 1.34: a firm tick straight from the motor, not the
                    // system's faint «touch feedback».
                    vibrate(
                        (call.argument<Int>("ms") ?: 20).toLong(),
                        call.argument<Int>("amplitude") ?: 160,
                    )
                    result.success(true)
                }
                "assistantSettings" -> {
                    // «Помощник по умолчанию» in Android settings.
                    val opened = listOf(
                        android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS,
                        android.provider.Settings.ACTION_VOICE_INPUT_SETTINGS,
                        android.provider.Settings.ACTION_SETTINGS,
                    ).any { action ->
                        try {
                            activity.startActivity(Intent(action))
                            true
                        } catch (_: Exception) {
                            false
                        }
                    }
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** An Intent from a widget, the tile or the shade. */
    fun accept(intent: Intent?) {
        // 1.31: Finora as the phone's assistant (power button / gesture).
        if (intent?.action == Intent.ACTION_ASSIST ||
            intent?.action == Intent.ACTION_VOICE_COMMAND
        ) {
            intent.action = Intent.ACTION_MAIN
            intent.putExtra(EXTRA_ACTION, "voice")
        }
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return
        intent.removeExtra(EXTRA_ACTION)
        pendingAction = action
        // Delivered now if the app is listening; otherwise kept for
        // «takeAction» when it starts.
        channel.invokeMethod(
            "action",
            action,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true && pendingAction == action) pendingAction = null
                }
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            },
        )
    }

    private fun vibrate(ms: Long, amplitude: Int) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= 31) {
                activity.getSystemService(android.os.VibratorManager::class.java)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                activity.getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
            } ?: return
            if (!vibrator.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= 26) {
                val strength = if (vibrator.hasAmplitudeControl()) {
                    amplitude.coerceIn(1, 255)
                } else {
                    android.os.VibrationEffect.DEFAULT_AMPLITUDE
                }
                vibrator.vibrate(android.os.VibrationEffect.createOneShot(ms, strength))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(ms)
            }
        } catch (_: Exception) {
        }
    }

    // ── Widgets ────────────────────────────────────────────────────────────

    private fun saveWidgets(data: Map<*, *>) {
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for ((key, value) in data) {
            if (key is String) prefs.putString(key, value?.toString() ?: "")
        }
        prefs.apply()
        FinoraWidgets.refreshAll(activity)
    }

    // ── Shade controls ─────────────────────────────────────────────────────

    private fun showShade(title: String, text: String) {
        val manager = activity.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(SHADE_CHANNEL, "Финора в шторке", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Быстрые действия Финоры: голос, расход, доход, скриншот"
                    setShowBadge(false)
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(activity, SHADE_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity).setPriority(Notification.PRIORITY_LOW)
        }
        fun action(label: String, action: String, code: Int) =
            Notification.Action.Builder(
                Icon.createWithResource(activity, R.drawable.ic_finora_tile),
                label,
                launch(activity, action, code),
            ).build()
        val notification = builder
            .setSmallIcon(R.drawable.ic_finora_tile)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(launch(activity, "open", 40))
            .addAction(action("Сказать", "voice", 41))
            .addAction(action("Расход", "expense", 42))
            .addAction(action("Скриншот", "scan", 43))
            .build()
        try {
            manager.notify(SHADE_ID, notification)
        } catch (_: SecurityException) {
            // Notifications not allowed: the Dart side asks for them first.
        }
    }

    private fun hideShade() {
        activity.getSystemService(NotificationManager::class.java)?.cancel(SHADE_ID)
    }

    fun close() {
        channel.setMethodCallHandler(null)
    }
}
