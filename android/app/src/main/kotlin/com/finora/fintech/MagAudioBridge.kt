package com.finora.fintech

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Sound of «Магистрали» (S21): a quiet music loop and short effects, all
 * made for the game and shipped in its assets. Music mixes with other
 * audio (no focus is taken); everything stops when the game or the app
 * goes to the background.
 */
class MagAudioBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "finora/mag_audio")
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
    private var active = false
    private var music = true
    private var sounds = true
    private var player: MediaPlayer? = null
    private var pool: SoundPool? = null
    private val effects = mutableMapOf<String, Int>()
    private val loaded = mutableSetOf<Int>()
    private val names = setOf("coin", "click", "build", "levelup", "horn", "error", "whoosh")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> {
                        active = call.argument<Boolean>("active") == true
                        music = call.argument<Boolean>("music") == true
                        sounds = call.argument<Boolean>("sound") == true
                        if (active && music) startMusic() else pauseMusic()
                        if (!active || !sounds) pool?.autoPause()
                        result.success(true)
                    }
                    "effect" -> {
                        val name = call.argument<String>("name") ?: "click"
                        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                        if (active && sounds && name in names) playEffect(name, volume)
                        result.success(null)
                    }
                    "stop" -> { release(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                release()
                result.error("MAG_AUDIO", "Не удалось включить звук игры", null)
            }
        }
    }

    private fun asset(file: String): String = FlutterInjector.instance().flutterLoader()
        .getLookupKeyForAsset("assets/finora/magistrali/audio/$file")

    private fun startMusic() {
        if (player == null) {
            player = MediaPlayer().apply {
                setAudioAttributes(attributes)
                context.assets.openFd(asset("music.ogg")).use { fd ->
                    setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                }
                isLooping = true
                setVolume(.32f, .32f)
                prepare()
            }
        }
        if (player?.isPlaying != true) player?.start()
    }

    private fun pauseMusic() {
        runCatching { player?.pause() }
    }

    private fun playEffect(name: String, volume: Float) {
        if (pool == null) {
            pool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attributes).build().also { sp ->
                sp.setOnLoadCompleteListener { _, id, status -> if (status == 0) loaded.add(id) }
                // Load every effect at once so the first one is not silent.
                for (n in names) {
                    effects[n] = context.assets.openFd(asset("$n.wav")).use { fd -> sp.load(fd, 1) }
                }
            }
        }
        val sp = pool ?: return
        val id = effects[name] ?: return
        val v = (.5f * volume).coerceIn(0f, 1f)
        if (loaded.contains(id)) sp.play(id, v, v, 1, 0, 1f)
    }

    fun suspend() {
        active = false
        pauseMusic()
        pool?.autoPause()
    }

    private fun release() {
        suspend()
        player?.release(); player = null
        pool?.release(); pool = null
        effects.clear(); loaded.clear()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        release()
    }
}
