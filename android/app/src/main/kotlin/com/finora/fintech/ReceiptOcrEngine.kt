package com.finora.fintech

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

internal class ReceiptOcrFailure(val code: String, message: String) : Exception(message)

internal class ReceiptOcrEngine(private val context: Context) {
    companion object {
        private const val MAX_BYTES = 20L * 1024 * 1024
        // A 1080 x 2401 screenshot must not be halved solely for being tall.
        // Decode within a pixel budget, then resize exactly instead of rounding
        // every ordinary bank screenshot down to the next power of two.
        private const val MAX_DECODE_EDGE = 8000
        private const val MAX_DECODE_PIXELS = 12_000_000L
        private const val MAX_OCR_EDGE = 6400
        private const val MAX_OCR_PIXELS = 8_000_000L
        private const val MAX_LINES = 2000
        private const val MAX_PIXELS = 100_000_000L
        private val MONEY = Regex(
            "(?<![\\d/.])(?:[+-]\\s*)?\\d(?:[ \\u00a0\\u202f]?\\d)*[,.]\\d{2}(?![\\d/.])|(?<!\\d)\\d[\\d ]*[₽$€]",
        )
        private val RECEIPT = Regex(
            "кассов|товарн|фискальн|(?<![а-я])ндс(?![а-я])|grand\\s+total|subtotal",
            RegexOption.IGNORE_CASE,
        )
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
        val decoded = decode(file)
        val bitmap = try {
            prepareTextImage(decoded)
        } finally {
            decoded.recycle()
        }
        var engine: TessBaseAPI? = null
        try {
            checkCancellation(cancelled)
            engine = TessBaseAPI()
            if (!engine.init(models.absolutePath, "rus+eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                throw ReceiptOcrFailure("OCR_MODELS_INVALID", "Bundled OCR models could not be loaded.")
            }
            checkCancellation(cancelled)
            engine.setVariable("user_defined_dpi", "300")
            val first = recognizePass(engine, bitmap, TessBaseAPI.PageSegMode.PSM_AUTO, cancelled)
            // Automatic page segmentation often separates or drops right-aligned
            // amounts on banking UIs. Retry sparse layouts; never concatenate
            // passes (which would create duplicate transactions).
            val receipt = RECEIPT.containsMatchIn(first.text)
            val retry = first.confidence < .72 || first.moneyCount == 0 ||
                (!receipt && bitmap.height > bitmap.width * 1.1)
            val chosen = if (retry) {
                checkCancellation(cancelled)
                val sparse = recognizePass(engine, bitmap, TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT, cancelled)
                choosePass(first, sparse)
            } else first
            return mapOf("text" to chosen.text, "confidence" to chosen.confidence, "lines" to chosen.lines)
        } finally {
            try {
                engine?.recycle()
            } finally {
                bitmap.recycle()
            }
        }
    }

    private data class Pass(
        val text: String,
        val confidence: Double,
        val lines: List<Map<String, Any>>,
    ) {
        val moneyCount: Int get() = MONEY.findAll(text).count()
        val usefulCharacters: Int get() = text.count { it.isLetterOrDigit() }
    }

    private fun recognizePass(
        engine: TessBaseAPI,
        bitmap: Bitmap,
        mode: Int,
        cancelled: AtomicBoolean,
    ): Pass {
        checkCancellation(cancelled)
        engine.setPageSegMode(mode)
        engine.setImage(bitmap)
        checkCancellation(cancelled)
        val text = engine.getUTF8Text() ?: ""
        checkCancellation(cancelled)
        if (text.length > 100_000) {
            throw ReceiptOcrFailure("OCR_OUTPUT_TOO_LARGE", "Recognized text is too long.")
        }
        val lines = mutableListOf<Map<String, Any>>()
        val iterator = engine.resultIterator
        if (iterator != null) {
            try {
                iterator.begin()
                val level = TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE
                do {
                    checkCancellation(cancelled)
                    val value = iterator.getUTF8Text(level)?.trim().orEmpty()
                    val box = iterator.getBoundingBox(level)
                    if (value.isEmpty() || box == null || box.size != 4 ||
                        box[2] <= box[0] || box[3] <= box[1]
                    ) continue
                    if (lines.size >= MAX_LINES) {
                        throw ReceiptOcrFailure("OCR_OUTPUT_TOO_LARGE", "Too many recognized lines.")
                    }
                    lines.add(mapOf(
                        "text" to value,
                        "left" to (box[0].toDouble() / bitmap.width).coerceIn(0.0, 1.0),
                        "top" to (box[1].toDouble() / bitmap.height).coerceIn(0.0, 1.0),
                        "right" to (box[2].toDouble() / bitmap.width).coerceIn(0.0, 1.0),
                        "bottom" to (box[3].toDouble() / bitmap.height).coerceIn(0.0, 1.0),
                        "confidence" to iterator.confidence(level).coerceIn(0f, 100f).toDouble() / 100.0,
                    ))
                } while (iterator.next(level))
            } finally {
                iterator.delete()
            }
        }
        return Pass(text, engine.meanConfidence().coerceIn(0, 100) / 100.0, lines)
    }

    private fun choosePass(first: Pass, sparse: Pass): Pass {
        if (sparse.usefulCharacters == 0) return first
        if (first.usefulCharacters == 0) return sparse
        // More monetary rows are useful only if text quality remains plausible.
        // A low-confidence noisy pass must not win simply by inventing digits.
        if (sparse.moneyCount > first.moneyCount &&
            sparse.confidence >= first.confidence - .12 &&
            sparse.usefulCharacters >= first.usefulCharacters * .6
        ) return sparse
        if (sparse.moneyCount >= first.moneyCount && sparse.confidence > first.confidence + .06) return sparse
        return first
    }

    /** Grayscale and invert dark UI backgrounds before segmentation. Text rows
     * keep their geometry; coordinates are normalized to the EXIF-corrected image.
     * These are temporary pixels only, never changes to the user's attachment. */
    private fun prepareTextImage(source: Bitmap): Bitmap {
        var dark = 0
        var samples = 0
        for (y in 1..9) for (x in 1..7) {
            val pixel = source.getPixel(source.width * x / 8, source.height * y / 10)
            val luma = .299 * ((pixel shr 16) and 255) + .587 * ((pixel shr 8) and 255) + .114 * (pixel and 255)
            if (luma < 112) dark++
            samples++
        }
        val invert = dark > samples * .6
        val usefulScale = if (source.width < 1400) min(1.6, 1400.0 / source.width) else 1.0
        val scale = min(usefulScale, min(
            MAX_OCR_EDGE.toDouble() / max(source.width, source.height),
            sqrt(MAX_OCR_PIXELS.toDouble() / (source.width.toLong() * source.height)),
        ))
        val width = max(1, (source.width * scale).roundToInt())
        val height = max(1, (source.height * scale).roundToInt())
        val target = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            val grayscale = ColorMatrix().apply { setSaturation(0f) }
            if (invert) {
                val reverse = ColorMatrix(floatArrayOf(
                    -1f, 0f, 0f, 0f, 255f,
                    0f, -1f, 0f, 0f, 255f,
                    0f, 0f, -1f, 0f, 255f,
                    0f, 0f, 0f, 1f, 0f,
                ))
                grayscale.postConcat(reverse)
            }
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                colorFilter = ColorMatrixColorFilter(grayscale)
            }
            val canvas = Canvas(target)
            canvas.drawColor(android.graphics.Color.WHITE)
            canvas.drawBitmap(source, null, android.graphics.Rect(0, 0, width, height), paint)
            return target
        } catch (error: Throwable) {
            target.recycle()
            throw error
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
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_DECODE_EDGE ||
            bounds.outWidth.toLong() * bounds.outHeight / (sample.toLong() * sample) > MAX_DECODE_PIXELS
        ) sample *= 2
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
