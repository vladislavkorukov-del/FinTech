package com.finora.fintech

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Voice entry (Finance 1.19): opens the system speech dialog and returns what
 * was heard as text. The system speech service records and recognizes, so
 * the app itself needs no microphone or network permission; offline
 * recognition is preferred where the phone has the Russian language pack.
 */
class VoiceInputBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val REQUEST = 4711
    }

    private val channel = MethodChannel(messenger, "finora/voice")
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(intent().resolveActivity(activity.packageManager) != null)
                "listen" -> listen(call.argument<String>("prompt"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun intent(prompt: String? = null) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            if (prompt != null) putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
        }

    private fun listen(prompt: String?, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("VOICE_BUSY", "Распознавание уже идёт", null)
            return
        }
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent(prompt), REQUEST)
        } catch (error: ActivityNotFoundException) {
            pending = null
            result.error("VOICE_UNAVAILABLE", "На телефоне нет службы распознавания речи", null)
        }
    }

    /** Returns true when the result belonged to voice input. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(emptyList<String>())
            return true
        }
        val heard = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS) ?: arrayListOf()
        result.success(heard.filter { it.isNotBlank() })
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.success(emptyList<String>())
        pending = null
    }
}
