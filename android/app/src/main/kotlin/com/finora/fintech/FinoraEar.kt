package com.finora.fintech

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.StorageService
import kotlin.math.max

/**
 * Finora's own ear (1.31): offline Russian speech recognition with Vosk,
 * reading the microphone directly — no system sounds, nothing leaves the
 * phone. It only ever listens while the app is on screen: for one phrase
 * after a tap (or the assistant gesture), or — when the person turns it on —
 * waiting for «Финора» until the app goes to the background.
 *
 * Two recognizers hear the same sound: one limited to the app's vocabulary
 * (precise for commands, numbers, categories, stores) and one free (any
 * name). Both texts go to the Dart parsers as hypotheses.
 */
class FinoraEar(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val MIC_REQUEST = 4712
        private const val RATE = 16000

        /** How the model hears «Финора» (the word is not in its dictionary). */
        val wakeWords = setOf("фигура", "фигуры", "финал", "финора")
    }

    private val channel = MethodChannel(messenger, "finora/ear")
    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var loading = false
    private val waiting = mutableListOf<(Boolean) -> Unit>()
    private var session: Session? = null
    private var micResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare { result.success(it) }
                "micAllowed" -> result.success(micAllowed())
                "requestMic" -> requestMic(result)
                "listen" -> {
                    val vocab = call.argument<List<String>>("vocabulary") ?: emptyList()
                    listen(vocab, result)
                }
                "wakeStart" -> {
                    val vocab = call.argument<List<String>>("vocabulary") ?: emptyList()
                    wakeStart(vocab)
                    result.success(true)
                }
                "stop" -> {
                    stop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Model ──────────────────────────────────────────────────────────────

    private fun prepare(done: (Boolean) -> Unit) {
        if (model != null) {
            done(true)
            return
        }
        waiting.add(done)
        if (loading) return
        loading = true
        // Copies the model from the APK to app storage once (checked by uuid).
        StorageService.unpack(
            activity,
            "model-ru",
            "model",
            { m: Model ->
                main.post {
                    model = m
                    loading = false
                    waiting.toList().forEach { it(true) }
                    waiting.clear()
                }
            },
            { _: java.io.IOException ->
                main.post {
                    loading = false
                    waiting.toList().forEach { it(false) }
                    waiting.clear()
                }
            },
        )
    }

    // ── Microphone permission ──────────────────────────────────────────────

    private fun micAllowed() = Build.VERSION.SDK_INT < 23 ||
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
        PackageManager.PERMISSION_GRANTED

    private fun requestMic(result: MethodChannel.Result) {
        if (micAllowed()) {
            result.success(true)
            return
        }
        micResult?.success(false)
        micResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
    }

    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != MIC_REQUEST) return false
        micResult?.success(micAllowed())
        micResult = null
        return true
    }

    // ── Listening ──────────────────────────────────────────────────────────

    private fun grammar(vocab: List<String>): String {
        val words = (vocab + wakeWords).map { it.lowercase().trim() }
            .filter { it.isNotEmpty() && !it.contains('"') }
            .distinct()
        val json = org.json.JSONArray()
        words.forEach { json.put(it) }
        json.put("[unk]")
        return json.toString()
    }

    /** One phrase: returns [vocabulary text, free text]. */
    private fun listen(vocab: List<String>, result: MethodChannel.Result) {
        if (!micAllowed()) {
            result.error("MIC", "Нет доступа к микрофону", null)
            return
        }
        prepare { ready ->
            val m = model
            if (!ready || m == null) {
                result.error("MODEL", "Не удалось загрузить распознавание речи", null)
                return@prepare
            }
            stop()
            var mine: Session? = null
            mine = Session(m, grammar(vocab), wake = false, useFree = true) { heard ->
                main.post {
                    if (session === mine) session = null
                    result.success(heard)
                }
            }
            session = mine
            mine.start()
        }
    }

    /**
     * Waits for «Финора» only (1.32): a tiny vocabulary — her name or
     * nothing — so other speech never turns into words; the app restarts it
     * after each wake and asks for the request with the accurate recognizer.
     */
    @Suppress("UNUSED_PARAMETER")
    private fun wakeStart(vocab: List<String>) {
        if (!micAllowed()) return
        prepare { ready ->
            val m = model ?: return@prepare
            if (!ready || session != null) return@prepare
            val names = org.json.JSONArray()
            wakeWords.forEach { names.put(it) }
            names.put("[unk]")
            session = Session(m, names.toString(), wake = true, useFree = false) { heard ->
                main.post {
                    session = null
                    channel.invokeMethod("wake", heard)
                }
            }.also { it.start() }
        }
    }

    fun stop() {
        session?.finish()
        session = null
    }

    fun close() {
        stop()
        channel.setMethodCallHandler(null)
        micResult?.success(false)
        micResult = null
    }

    private fun text(json: String, key: String = "text") =
        try {
            JSONObject(json).optString(key, "").trim()
        } catch (_: Exception) {
            ""
        }

    private inner class Session(
        private val model: Model,
        private val grammar: String,
        private val wake: Boolean,
        private val useFree: Boolean,
        private val done: (List<String>) -> Unit,
    ) : Thread("finora-ear") {
        @Volatile
        private var running = true
        private var delivered = false

        fun finish() {
            running = false
        }

        private fun deliver(heard: List<String>) {
            if (delivered) return
            delivered = true
            done(heard)
        }

        override fun run() {
            var exact: Recognizer? = null
            var free: Recognizer? = null
            var record: AudioRecord? = null
            try {
                exact = Recognizer(model, RATE.toFloat(), grammar)
                if (useFree) free = Recognizer(model, RATE.toFloat())
                val min = AudioRecord.getMinBufferSize(
                    RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                @Suppress("MissingPermission")
                record = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    max(min, RATE),
                )
                if (record.state != AudioRecord.STATE_INITIALIZED) {
                    if (!wake) deliver(emptyList())
                    return
                }
                record.startRecording()
                val buffer = ShortArray(RATE / 10)
                val started = System.currentTimeMillis()
                var lastPartial = ""
                var heardAt = 0L
                while (running) {
                    val n = record.read(buffer, 0, buffer.size)
                    if (n <= 0) continue
                    val ended = exact.acceptWaveForm(buffer, n)
                    free?.acceptWaveForm(buffer, n)
                    val now = System.currentTimeMillis()
                    if (ended) {
                        val said = text(exact.result)
                        val loose = free?.let { text(it.finalResult) } ?: ""
                        if (wake) {
                            val first = said.split(' ').firstOrNull() ?: ""
                            if (first in wakeWords) {
                                deliver(listOf(said, loose))
                                return
                            }
                            continue
                        }
                        if (said.isNotEmpty() || loose.isNotEmpty()) {
                            deliver(listOf(loose, said).filter { it.isNotEmpty() })
                            return
                        }
                        continue
                    }
                    if (!wake) {
                        val partial = text(exact.partialResult, "partial")
                        if (partial.isNotEmpty()) heardAt = now
                        if (partial != lastPartial) {
                            lastPartial = partial
                            main.post { channel.invokeMethod("partial", partial) }
                        }
                        // Nothing said for 6 s, or a phrase longer than 15 s.
                        if ((heardAt == 0L && now - started > 6000) || now - started > 15000) {
                            val said = text(exact.finalResult)
                            val loose = free?.let { text(it.finalResult) } ?: ""
                            deliver(listOf(loose, said).filter { it.isNotEmpty() })
                            return
                        }
                    }
                }
                if (!wake) deliver(emptyList())
            } catch (_: Exception) {
                if (!wake) deliver(emptyList())
            } finally {
                try {
                    record?.stop()
                } catch (_: Exception) {
                }
                record?.release()
                exact?.close()
                free?.close()
            }
        }
    }
}
