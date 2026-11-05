package com.finora.fintech

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Copies a single shared content URI into private cache, never starts OCR. */
internal class ReceiptShareBridge(context: Context, messenger: BinaryMessenger) : AutoCloseable {
    private val app = context.applicationContext
    private val channel = MethodChannel(messenger, "finora/receipt_share")
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val executor = ThreadPoolExecutor(
        1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue(1),
        { task -> Thread(task, "finance-receipt-share") },
    )
    private var pending: File? = null // Main thread owns pending and pendingError.
    private var pendingError: String? = null
    @Volatile private var activeCancellation: CancellationSignal? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "takeSharedImage") {
                result.notImplemented()
            } else {
                val error = pendingError
                pendingError = null
                if (error != null) {
                    result.error(error, "Shared image could not be imported.", null)
                } else {
                    val file = pending
                    pending = null
                    result.success(file?.absolutePath)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    fun accept(intent: Intent?) {
        if (closed.get() || intent?.action != Intent.ACTION_SEND) return
        val uri = try {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                ?: intent.clipData?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.uri
        } catch (_: RuntimeException) { null }
        val declaredType = intent.type
        if (uri?.scheme != "content" || declaredType?.startsWith("image/") != true) {
            reportFailure("SHARE_INVALID_IMAGE")
            return
        }
        try {
            executor.execute { copy(uri, declaredType) }
        } catch (_: RejectedExecutionException) {
            reportFailure("SHARE_BUSY")
        }
    }

    private fun copy(uri: Uri, declaredType: String) {
        val signal = CancellationSignal()
        activeCancellation = signal
        var target: File? = null
        var handedOff = false
        try {
            if (closed.get()) return
            val actualType = app.contentResolver.getType(uri)
            if (actualType != null && !actualType.startsWith("image/")) {
                throw ShareFailure("SHARE_INVALID_IMAGE")
            }
            val directory = File(app.cacheDir, "receipt_shares")
            if (!directory.isDirectory && !directory.mkdirs()) throw ShareFailure("SHARE_FAILED")
            val extension = when (actualType ?: declaredType) {
                "image/png" -> "png"
                "image/jpeg" -> "jpg"
                "image/webp" -> "webp"
                "image/heic", "image/heif" -> "heic"
                else -> "image"
            }
            val file = File(directory, "${UUID.randomUUID()}.$extension")
            target = file
            val descriptor = app.contentResolver.openFileDescriptor(uri, "r", signal)
                ?: throw ShareFailure("SHARE_FAILED")
            ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                if (descriptor.statSize > MAX_BYTES) throw ShareFailure("SHARE_IMAGE_TOO_LARGE")
                    file.outputStream().use { output ->
                        val buffer = ByteArray(16 * 1024)
                        var total = 0L
                        while (true) {
                            if (closed.get() || signal.isCanceled) throw ShareFailure("SHARE_CANCELLED")
                            val size = input.read(buffer)
                            if (size < 0) break
                            total += size
                            if (total > MAX_BYTES) throw ShareFailure("SHARE_IMAGE_TOO_LARGE")
                            output.write(buffer, 0, size)
                        }
                        if (total == 0L) throw ShareFailure("SHARE_INVALID_IMAGE")
                    }
            }
            val completed = file
            main.post {
                if (closed.get()) {
                    completed.delete()
                } else {
                    pending?.delete()
                    pending = completed
                    pendingError = null
                    channel.invokeMethod("imageAvailable", null)
                }
            }
            handedOff = true
        } catch (error: ShareFailure) {
            if (!closed.get()) reportFailure(error.code)
        } catch (_: Exception) {
            if (!closed.get()) reportFailure("SHARE_FAILED")
        } finally {
            if (!handedOff) target?.delete()
            activeCancellation = null
        }
    }

    private fun reportFailure(code: String) {
        main.post {
            if (!closed.get()) {
                pending?.delete()
                pending = null
                pendingError = code
                // Also retained until takeSharedImage, so a cold-start listener
                // cannot miss an error emitted before Dart attaches its handler.
                channel.invokeMethod("shareError", mapOf("code" to code))
            }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        activeCancellation?.cancel()
        executor.shutdownNow()
        pending?.delete()
        pending = null
        pendingError = null
    }

    private class ShareFailure(val code: String) : Exception()
    companion object { private const val MAX_BYTES = 20L * 1024 * 1024 }
}
