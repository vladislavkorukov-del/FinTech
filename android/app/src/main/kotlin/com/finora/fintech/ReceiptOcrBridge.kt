package com.finora.fintech

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** A bounded, serialized native worker. Never logs image paths or recognized text. */
internal class ReceiptOcrBridge(context: Context, messenger: BinaryMessenger) : AutoCloseable {
    private val app = context.applicationContext
    private val channel = MethodChannel(messenger, "finora/ocr")
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val requests = ConcurrentHashMap<String, Request>()
    private val executor = ThreadPoolExecutor(
        1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue(1),
        { task -> Thread(task, "finance-offline-ocr") },
    )

    private class Request(val result: MethodChannel.Result) {
        val cancelled = AtomicBoolean(false)
        val delivered = AtomicBoolean(false)
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val path = arguments?.get("path") as? String
                    val language = arguments?.get("language") as? String
                    val id = arguments?.get("requestId") as? String ?: "default"
                    if (path.isNullOrBlank() || language != "rus+eng" || id.isBlank() || id.length > 128) {
                        result.error("OCR_INVALID_ARGUMENT", "Invalid OCR request.", null)
                    } else {
                        recognize(id, path, result)
                    }
                }
                "cancel" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("requestId") as? String ?: "default"
                    requests[id]?.let {
                        it.cancelled.set(true)
                        fail(it, "OCR_CANCELLED", "Recognition cancelled.")
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun recognize(id: String, path: String, result: MethodChannel.Result) {
        if (closed.get()) {
            result.error("OCR_CANCELLED", "Recognition unavailable after activity close.", null)
            return
        }
        val request = Request(result)
        if (requests.putIfAbsent(id, request) != null) {
            result.error("OCR_BUSY", "Recognition is already running.", null)
            return
        }
        try {
            executor.execute {
                try {
                    val value = ReceiptOcrEngine(app).recognize(path, request.cancelled)
                    deliver(request) { request.result.success(value) }
                } catch (error: ReceiptOcrFailure) {
                    fail(request, error.code, error.message ?: "Recognition failed.")
                } catch (_: OutOfMemoryError) {
                    fail(request, "OCR_IMAGE_TOO_LARGE", "Image exceeds available memory.")
                } catch (_: Exception) {
                    fail(request, "OCR_FAILED", "Offline recognition failed.")
                } catch (_: LinkageError) {
                    fail(request, "OCR_UNAVAILABLE", "OCR engine unavailable on this device.")
                } finally {
                    requests.remove(id, request)
                }
            }
        } catch (_: RejectedExecutionException) {
            requests.remove(id, request)
            fail(request, "OCR_BUSY", "Recognition is already running.")
        }
    }

    private fun deliver(request: Request, action: () -> Unit) {
        main.post {
            if (request.delivered.compareAndSet(false, true)) {
                if (request.cancelled.get() || closed.get()) {
                    request.result.error("OCR_CANCELLED", "Recognition cancelled.", null)
                } else {
                    action()
                }
            }
        }
    }

    private fun fail(request: Request, code: String, message: String) =
        deliver(request) { request.result.error(code, message, null) }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        requests.values.forEach {
            it.cancelled.set(true)
            fail(it, "OCR_CANCELLED", "Recognition cancelled.")
        }
        requests.clear()
        // UTF8 recognition has no documented thread-safe stop API. Never recycle
        // a native engine from this thread; the worker owns it until finally.
        executor.shutdownNow()
    }
}
