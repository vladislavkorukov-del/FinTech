package com.finora.fintech

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Finora outside the app screen (1.27): home-screen widgets, the Quick
 * Settings tile and the shade controls open the app with an action; and,
 * when the person turns it on, she answers to her name while the app is open.
 */
class FinoraBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val EXTRA_ACTION = "finora_action"
        const val MIC_REQUEST = 4712
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

        /** Words that sound like her name in Russian and English. */
        private val names = listOf("финор", "фенор", "финар", "финур", "винор", "finor", "fenor", "phinor")

        fun hears(text: String): Boolean {
            val t = text.lowercase().replace('ё', 'е')
            return names.any { t.contains(it) }
        }
    }

    private val channel = MethodChannel(messenger, "finora/system")
    private val main = Handler(Looper.getMainLooper())
    private var pendingAction: String? = null
    private var recognizer: SpeechRecognizer? = null
    private var wakeOn = false
    private var micResult: MethodChannel.Result? = null

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
                "micAllowed" -> result.success(micAllowed())
                "requestMic" -> requestMic(result)
                "wakeStart" -> {
                    wakeOn = true
                    startWake()
                    result.success(micAllowed())
                }
                "wakeStop" -> {
                    stopWake()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** An Intent from a widget, the tile or the shade. */
    fun accept(intent: Intent?) {
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

    // ── «Финора» ───────────────────────────────────────────────────────────

    private fun micAllowed() = Build.VERSION.SDK_INT < 23 ||
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun requestMic(result: MethodChannel.Result) {
        if (micAllowed()) {
            result.success(true)
            return
        }
        micResult?.success(false)
        micResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
    }

    /** Returns true when the answer was about the microphone. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != MIC_REQUEST) return false
        micResult?.success(micAllowed())
        micResult = null
        return true
    }

    private fun startWake() {
        if (!wakeOn || !micAllowed() || recognizer != null) return
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) return
        val r = if (Build.VERSION.SDK_INT >= 33 &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        ) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        } else {
            SpeechRecognizer.createSpeechRecognizer(activity)
        }
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
            // The whole phrase is waited for: «Финора, покажи расходы».
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onResults(results: Bundle?) {
                val heard = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?: arrayListOf()
                val match = heard.firstOrNull { hears(it) }
                release()
                if (match != null && wakeOn) {
                    wakeOn = false
                    channel.invokeMethod("wake", heard.filter { it.isNotBlank() })
                } else {
                    again(300)
                }
            }
            override fun onError(error: Int) {
                release()
                when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> wakeOn = false
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> again(1500)
                    else -> again(400)
                }
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
        }
        try {
            r.startListening(intent)
        } catch (_: Exception) {
            release()
            again(1500)
        }
    }

    private fun again(delay: Long) {
        if (!wakeOn) return
        main.postDelayed({ startWake() }, delay)
    }

    private fun release() {
        recognizer?.let {
            try {
                it.cancel()
                it.destroy()
            } catch (_: Exception) {
            }
        }
        recognizer = null
    }

    fun stopWake() {
        wakeOn = false
        main.removeCallbacksAndMessages(null)
        release()
    }

    fun close() {
        stopWake()
        channel.setMethodCallHandler(null)
        micResult?.success(false)
        micResult = null
    }
}
