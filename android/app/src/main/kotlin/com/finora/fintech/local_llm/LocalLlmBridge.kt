package com.finora.fintech.local_llm

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Single CPU inference owner. JNI work never runs on Android's UI thread.
 * Cancellation only flips an atomic flag; unload is queued behind generation.
 * No prompts or responses are logged, persisted or sent over the network here.
 */
class LocalLlmBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ComponentCallbacks2 {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "finora/local_llm")
    private val events = EventChannel(messenger, "finora/local_llm/events")
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var activeId: String? = null
    @Volatile private var closed = false
    @Volatile private var loadedPath: String? = null
    @Volatile private var loadMs = 0.0
    @Volatile private var pressureStop = false
    @Volatile private var lastMetrics: Map<String, Any?> = emptyMap()
    private val idleUnload = Runnable { releaseInBackground() }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        app.registerComponentCallbacks(this)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("closed", "Модуль локальной модели закрыт", null); return }
        if (!available) { result.error("unsupported", "Локальная модель недоступна на этом устройстве", null); return }
        when (call.method) {
            "storage", "freeStorage" -> {
                try {
                    val path = call.argument<String>("path") ?: app.filesDir.path
                    val free = StatFs(privatePath(path).path).availableBytes
                    result.success(if (call.method == "freeStorage") free else mapOf("freeBytes" to free))
                } catch (_: Exception) { result.error("storage", "Не удалось проверить свободное место", null) }
            }
            "diagnostics" -> result.success(diagnostics())
            "cancel" -> {
                val id = call.argument<String>("id")
                if (id == null || id == activeId) nativeCancel()
                result.success(null)
            }
            "unload" -> {
                nativeCancel()
                main.removeCallbacks(idleUnload)
                worker.execute {
                    nativeUnload(); loadedPath = null
                    reply(result, mapOf("loaded" to false))
                }
            }
            "load" -> {
                if (nativeBusy.get()) { result.error("busy", "Остановите текущий ответ", null); return }
                val path = call.argument<String>("path")
                if (path == null) { result.error("invalid", "Не указан каталог модели", null); return }
                worker.execute {
                    try {
                        val directory = privatePath(path)
                        if (loadedPath != directory.path) {
                            memoryPreflight(directory)
                            val config = prepareTextConfig(directory)
                            loadedPath = null
                            loadMs = nativeLoad(config.path)
                            loadedPath = directory.path
                        }
                        scheduleIdle()
                        reply(result, diagnostics())
                    } catch (e: Exception) { failure(result, e) }
                }
            }
            "tokenize" -> worker.execute {
                try {
                    val messages = validatedMessages(call)
                    if (loadedPath == null) throw IllegalStateException("Модель не загружена")
                    reply(result, mapOf("tokens" to nativeTokenize(messages.first, messages.second)))
                    scheduleIdle()
                } catch (e: Exception) { failure(result, e) }
            }
            "generate" -> {
                val id = call.argument<String>("id")
                val maxTokens = call.argument<Number>("maxTokens")?.toInt() ?: 256
                val contextTokens = call.argument<Number>("contextTokens")?.toInt() ?: 2048
                if (id.isNullOrBlank() || id.length > 100 || maxTokens !in 1..256 || contextTokens !in 256..2048) {
                    result.error("invalid", "Недопустимые параметры запроса", null); return
                }
                if (!nativeBusy.compareAndSet(false, true)) { result.error("busy", "Ответ уже готовится", null); return }
                val messages = try { validatedMessages(call) } catch (e: Exception) {
                    nativeBusy.set(false); failure(result, e); return
                }
                main.removeCallbacks(idleUnload)
                activeId = id; pressureStop = false; nativePrepare()
                worker.execute {
                    try {
                        if (loadedPath == null) throw IllegalStateException("Модель не загружена")
                        if (memoryInfo().lowMemory) throw IllegalStateException("Недостаточно свободной памяти. Используйте базовый режим")
                        val raw = nativeGenerate(messages.first, messages.second, maxTokens, contextTokens)
                        val reason = if (pressureStop) "memory_pressure" else raw[1]
                        val metrics = mapOf<String, Any?>(
                            "promptTokens" to raw[2].toInt(), "outputTokens" to raw[3].toInt(),
                            "loadMs" to raw[4].toDouble(), "firstTokenMs" to raw[5].toDouble(),
                            "totalMs" to raw[6].toDouble(), "prefillMs" to raw[7].toDouble(),
                            "decodeMs" to raw[8].toDouble(), "runtime" to RUNTIME, "backend" to "cpu",
                            "processPssBytes" to processPssBytes(), "thermalStatus" to thermalStatus(),
                        )
                        lastMetrics = metrics + mapOf("reason" to reason)
                        val answer = mapOf("id" to id, "text" to raw[0], "reason" to reason, "metrics" to metrics)
                        emit(answer + mapOf("type" to "done"))
                        reply(result, answer)
                    } catch (e: Exception) { failure(result, e) }
                    finally {
                        activeId = null; nativeBusy.set(false)
                        if (pressureStop) { nativeUnload(); loadedPath = null }
                        scheduleIdle()
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun validatedMessages(call: MethodCall): Pair<Array<String>, Array<String>> {
        val list = call.argument<List<Map<String, String>>>("messages")
            ?: throw IllegalArgumentException("Не указаны сообщения")
        require(list.isNotEmpty() && list.size <= 64) { "Слишком много сообщений" }
        val roles = list.map { it["role"] ?: "" }
        require(roles.all { it in listOf("system", "user", "assistant") }) { "Недопустимая роль" }
        val contents = list.map { it["content"] ?: "" }
        require(contents.all { it.length <= 50000 }) { "Сообщение слишком велико" }
        return roles.toTypedArray() to contents.toTypedArray()
    }

    /** Keep verified upstream files immutable; derived runtime configuration is
     * separate and regenerated. Text-only mRoPE is verified by the host probe. */
    private fun prepareTextConfig(directory: File): File {
        require(directory.isDirectory) { "Каталог модели не найден" }
        for (name in listOf("config.json", "llm_config.json", "llm.mnn", "llm.mnn.weight")) {
            require(File(directory, name).isFile) { "Неполная модель. Установите её заново" }
        }
        val tokenizer = when {
            File(directory, "tokenizer.mtok").isFile -> "tokenizer.mtok"
            File(directory, "tokenizer.txt").isFile -> "tokenizer.txt"
            else -> throw IllegalArgumentException("Не найден токенизатор")
        }
        val metadata = JSONObject(File(directory, "llm_config.json").readText())
        metadata.put("is_visual", false)
        val jinja = metadata.optJSONObject("jinja") ?: JSONObject()
        jinja.put("context", JSONObject().put("enable_thinking", false))
        metadata.put("jinja", jinja)
        File(directory, "finora_llm_config.json").writeText(metadata.toString())
        val config = JSONObject(File(directory, "config.json").readText())
        config.put("llm_config", "finora_llm_config.json").put("tokenizer_file", tokenizer)
            .put("backend_type", "cpu").put("thread_num", 4).put("max_new_tokens", 256)
            .put("sampler_type", "greedy").put("timeout_ms", 120000).put("reuse_kv", false).put("prompt_cache", false)
            .put("jinja", jinja)
        return File(directory, "finora_config.json").also { it.writeText(config.toString()) }
    }

    private fun privatePath(path: String): File {
        val directory = File(path).canonicalFile
        val root = app.dataDir.canonicalFile
        require(directory.path == root.path || directory.path.startsWith(root.path + File.separator)) { "Модель должна находиться в памяти приложения" }
        return directory
    }
    private fun memoryInfo() = ActivityManager.MemoryInfo().also {
        (app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(it)
    }
    private fun memoryPreflight(directory: File) {
        val info = memoryInfo()
        val weightBytes = File(directory, "llm.mnn.weight").length()
        val safetyBudget = weightBytes * 2 + 512L * 1024 * 1024
        require(!info.lowMemory && info.availMem >= safetyBudget) {
            "Недостаточно свободной памяти для этой модели. Закройте другие приложения или выберите 0.8B"
        }
    }
    private fun processPssBytes(): Long = Debug.MemoryInfo().let { Debug.getMemoryInfo(it); it.totalPss.toLong() * 1024 }
    private fun thermalStatus(): Int? = if (Build.VERSION.SDK_INT >= 29) (app.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus else null
    private fun diagnostics(): Map<String, Any?> = mapOf(
        "supported" to available, "loaded" to (loadedPath != null), "runtime" to RUNTIME,
        "backend" to "cpu", "loadMs" to loadMs, "processPssBytes" to processPssBytes(),
        "availableMemoryBytes" to memoryInfo().availMem, "thermalStatus" to thermalStatus(),
        "busy" to nativeBusy.get(), "lastGeneration" to lastMetrics,
    )

    // JNI calls these only on worker. They never log/retain generated text.
    @Suppress("unused")
    private fun onNativeDelta(bytes: ByteArray) {
        activeId?.let { emit(mapOf("id" to it, "type" to "delta", "text" to bytes.toString(Charsets.UTF_8))) }
    }
    @Suppress("unused")
    private fun shouldStopForPressure(): Boolean {
        val info = memoryInfo()
        if (info.lowMemory || info.availMem < 256L * 1024 * 1024 || (thermalStatus() ?: 0) >= PowerManager.THERMAL_STATUS_SEVERE) pressureStop = true
        return pressureStop || closed
    }
    private fun emit(event: Map<String, Any?>) { main.post { if (!closed) sink?.success(event) } }
    private fun reply(result: MethodChannel.Result, value: Any?) { main.post { result.success(value) } }
    private fun failure(result: MethodChannel.Result, e: Exception) {
        lastMetrics = mapOf("error" to e.javaClass.simpleName)
        main.post { result.error("local_model", e.message ?: "Ошибка локальной модели", null) }
    }
    private fun scheduleIdle() { main.post { main.removeCallbacks(idleUnload); if (!closed) main.postDelayed(idleUnload, 120000) } }
    fun releaseInBackground() {
        if (!available) return
        nativeCancel(); main.removeCallbacks(idleUnload)
        worker.execute { nativeUnload(); loadedPath = null }
    }
    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) { pressureStop = true; releaseInBackground() }
    }
    override fun onLowMemory() { pressureStop = true; releaseInBackground() }
    override fun onConfigurationChanged(newConfig: Configuration) {}
    fun close() {
        closed = true; methods.setMethodCallHandler(null); events.setStreamHandler(null)
        app.unregisterComponentCallbacks(this); sink = null; releaseInBackground()
    }

    private external fun nativeLoad(path: String): Double
    private external fun nativeTokenize(roles: Array<String>, contents: Array<String>): Int
    private external fun nativeGenerate(roles: Array<String>, contents: Array<String>, maxTokens: Int, contextTokens: Int): Array<String>
    private external fun nativePrepare()
    private external fun nativeCancel()
    private external fun nativeUnload()
    companion object {
        const val RUNTIME = "MNN-3.6.2-b0239771"
        private val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread({
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
                runnable.run()
            }, "Finora-Local-LLM")
        }
        private val nativeBusy = AtomicBoolean(false)
        private val available = try { System.loadLibrary("finora_local_llm"); true } catch (_: UnsatisfiedLinkError) { false }
    }
}
