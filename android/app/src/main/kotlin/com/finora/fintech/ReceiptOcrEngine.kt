package com.finora.fintech

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

internal class ReceiptOcrFailure(val code: String, message: String) : Exception(message)

internal class ReceiptOcrEngine(private val context: Context) {
    companion object {
        private const val MAX_BYTES = 20L * 1024 * 1024
        private const val MAX_EDGE = 2400
        private const val MAX_PIXELS = 100_000_000L
        private val MODELS = mapOf(
            "rus" to "e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225",
            "eng" to "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
        )
    }

    fun recognize(path: String, cancelled: AtomicBoolean): Map<String, Any> {
        checkCancellation(cancelled)
        val file = privateImage(path)
        val models = prepareModels(cancelled)
        checkCancellation(cancelled)
        val bitmap = decode(file)
        var engine: TessBaseAPI? = null
        try {
            checkCancellation(cancelled)
            engine = TessBaseAPI()
            if (!engine.init(models.absolutePath, "rus+eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                throw ReceiptOcrFailure("OCR_MODELS_INVALID", "Bundled OCR models could not be loaded.")
            }
            checkCancellation(cancelled)
            engine.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            engine.setVariable("user_defined_dpi", "300")
            engine.setImage(bitmap)
            checkCancellation(cancelled)
            val text = engine.getUTF8Text() ?: ""
            checkCancellation(cancelled)
            if (text.length > 100_000) {
                throw ReceiptOcrFailure("OCR_OUTPUT_TOO_LARGE", "Recognized text is too long.")
            }
            return mapOf("text" to text, "confidence" to engine.meanConfidence().coerceIn(0, 100) / 100.0)
        } finally {
            try {
                engine?.recycle()
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun privateImage(path: String): File {
        if (!File(path).isAbsolute || path.contains("://")) {
            throw ReceiptOcrFailure("OCR_INVALID_PATH", "Only private local images are accepted.")
        }
        val file = File(path).canonicalFile
        val root = File(context.applicationInfo.dataDir).canonicalFile
        if (!file.path.startsWith(root.path + File.separator) || !file.isFile) {
            throw ReceiptOcrFailure("OCR_INVALID_PATH", "Image must be inside app private storage.")
        }
        if (file.length() !in 1..MAX_BYTES) {
            throw ReceiptOcrFailure("OCR_IMAGE_TOO_LARGE", "Image must be between 1 byte and 20 MiB.")
        }
        return file
    }

    private fun prepareModels(cancelled: AtomicBoolean): File {
        val root = File(context.noBackupFilesDir, "receipt_ocr/v1")
        val directory = File(root, "tessdata")
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw ReceiptOcrFailure("OCR_MODELS_MISSING", "Cannot prepare bundled OCR models.")
        }
        for ((language, expected) in MODELS) {
            checkCancellation(cancelled)
            val target = File(directory, "$language.traineddata")
            if (target.isFile && sha256(target) == expected) continue
            val temporary = File(directory, "$language.tmp")
            try {
                val lookup = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/ocr/tessdata/$language.traineddata")
                context.assets.open(lookup).use { input ->
                    temporary.outputStream().use { output -> input.copyTo(output) }
                }
                if (sha256(temporary) != expected) {
                    throw ReceiptOcrFailure("OCR_MODELS_INVALID", "Bundled OCR model checksum mismatch.")
                }
                if (!temporary.renameTo(target)) {
                    throw ReceiptOcrFailure("OCR_MODELS_MISSING", "Cannot install bundled OCR models.")
                }
            } catch (failure: ReceiptOcrFailure) {
                throw failure
            } catch (_: Exception) {
                throw ReceiptOcrFailure("OCR_MODELS_MISSING", "Bundled OCR models are unavailable.")
            } finally {
                temporary.delete()
            }
        }
        return root
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val size = input.read(buffer)
                if (size < 0) break
                digest.update(buffer, 0, size)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private fun decode(file: File): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0 ||
            bounds.outWidth.toLong() * bounds.outHeight > MAX_PIXELS
        ) {
            throw ReceiptOcrFailure("OCR_INVALID_IMAGE", "Unsupported or oversized image dimensions.")
        }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_EDGE) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeFile(file.path, options)
            ?: throw ReceiptOcrFailure("OCR_INVALID_IMAGE", "Image cannot be decoded.")
        try {
            val orientation = ExifInterface(file).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
            )
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            }
            if (matrix.isIdentity) return bitmap
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (rotated !== bitmap) bitmap.recycle()
            return rotated
        } catch (error: Throwable) {
            bitmap.recycle()
            throw error
        }
    }

    private fun checkCancellation(cancelled: AtomicBoolean) {
        if (cancelled.get() || Thread.currentThread().isInterrupted) {
            throw ReceiptOcrFailure("OCR_CANCELLED", "Recognition cancelled.")
        }
    }
}
