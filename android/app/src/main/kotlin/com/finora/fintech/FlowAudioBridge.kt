package com.finora.fintech

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Build
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Local game audio. Never keeps playing when the Activity/level is paused. */
class FlowAudioBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "finora/flow_audio")
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private var active = false
    private var music = false
    private var sounds = true
    private var focused = false
    private var hasFocusRequest = false
    private var player: MediaPlayer? = null
    private var pool: SoundPool? = null
    private val effects = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        focused = change == AudioManager.AUDIOFOCUS_GAIN
        if (focused && active && music) startMusic() else pauseMusic()
    }
    private var request: AudioFocusRequest? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> {
                        active = call.argument<Boolean>("active") == true
                        music = call.argument<Boolean>("music") == true
                        sounds = call.argument<Boolean>("sound") == true
                        if (active && music) {
                            if (requestFocus()) startMusic()
                        } else {
                            pauseMusic()
                            abandonFocus()
                        }
                        if (!active || !sounds) pool?.autoPause()
                        result.success(true)
                    }
                    "effect" -> {
                        if (active && sounds) playEffect(call.argument<String>("name") ?: "tap")
                        result.success(null)
                    }
                    "stop" -> { releaseAudio(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                releaseAudio()
                result.error("FLOW_AUDIO", "Не удалось включить звук игры", null)
            }
        }
    }

    private fun asset(name: String): String = FlutterInjector.instance().flutterLoader()
        .getLookupKeyForAsset("assets/finora/match3/audio/$name.wav")

    private fun pauseMusic() {
        runCatching { player?.pause() }
    }

    private fun startMusic() {
        if (!active || !music || !focused) return
        if (player == null) {
            player = MediaPlayer().apply {
                setAudioAttributes(attributes)
                context.assets.openFd(asset("terrace")).use { fd -> setDataSource(fd.fileDescriptor, fd.startOffset, fd.length) }
                isLooping = true
                setVolume(.28f, .28f)
                prepare()
            }
        }
        if (player?.isPlaying != true) player?.start()
    }

    private fun playEffect(name: String) {
        if (name != "tap" && name != "chime") return
        if (pool == null) {
            pool = SoundPool.Builder().setMaxStreams(3).setAudioAttributes(attributes).build().also { sound ->
                sound.setOnLoadCompleteListener { _, id, status ->
                    if (status == 0) {
                        loaded.add(id)
                        if (active && sounds) sound.play(id, .28f, .28f, 1, 0, 1f)
                    }
                }
            }
        }
        val sound = pool ?: return
        val id = effects[name] ?: context.assets.openFd(asset(name)).use { fd -> sound.load(fd, 1) }.also { effects[name] = it }
        if (loaded.contains(id)) sound.play(id, .28f, .28f, 1, 0, 1f)
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        if (focused) return true
        val status = if (Build.VERSION.SDK_INT >= 26) {
            val focus = request ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener).build().also { request = it }
            manager.requestAudioFocus(focus)
        } else manager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        hasFocusRequest = status == AudioManager.AUDIOFOCUS_REQUEST_GRANTED || status == AudioManager.AUDIOFOCUS_REQUEST_DELAYED
        focused = status == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return focused
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (!hasFocusRequest) return
        hasFocusRequest = false
        if (Build.VERSION.SDK_INT >= 26) request?.let { manager.abandonAudioFocusRequest(it) }
        else manager.abandonAudioFocus(focusListener)
        focused = false
    }

    fun suspend() {
        active = false
        pauseMusic()
        pool?.autoPause()
        abandonFocus()
    }

    private fun releaseAudio() {
        suspend()
        player?.release(); player = null
        pool?.release(); pool = null
        effects.clear(); loaded.clear()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        releaseAudio()
    }
}
