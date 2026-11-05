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
        // Broader receipt evidence for the focused total pass (not for the
        // sparse retry decision above, which keeps its 1.5 behavior).
        private val RECEIPT_LIKE = Regex(
            "кассов|товарн|фискальн|(?<![а-я])ндс(?![а-я])|кассир|безнал|наличн|итог|к\\s*оплате|grand\\s+total|subtotal",
            RegexOption.IGNORE_CASE,
        )
        private const val MAX_FOCUS_BANDS = 3
        private const val MAX_FOCUS_ROWS = 40
        private const val MAX_FOCUS_PIXELS = 4_000_000L
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
            // Second, enlarged pass over the receipt's total band. It adds
            // evidence only; the main text/lines stay exactly as recognized.
            val focus = if (RECEIPT_LIKE.containsMatchIn(chosen.text)) {
                focusTotal(engine, bitmap, chosen, cancelled)
            } else emptyList()
            return mapOf(
                "text" to chosen.text,
                "confidence" to chosen.confidence,
                "lines" to chosen.lines,
                "focus" to focus,
            )
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

    /** Re-reads the band around a (possibly OCR-damaged) «ИТОГ» row at a
     * larger scale with flattened lighting; if no total row was read, the
     * lower part of the receipt. Failures (other than cancellation) keep the
     * main result and return no focus rows. */
    private fun focusTotal(
        engine: TessBaseAPI,
        bitmap: Bitmap,
        chosen: Pass,
        cancelled: AtomicBoolean,
    ): List<String> {
        val rows = mutableListOf<String>()
        try {
            val bands = mutableListOf<Triple<Int, Int, Double>>()
            for (line in chosen.lines) {
                if (bands.size >= MAX_FOCUS_BANDS) break
                if (!totalLike(line["text"] as String)) continue
                val top = (line["top"] as Double) * bitmap.height
                val bottom = (line["bottom"] as Double) * bitmap.height
                val height = max(4.0, bottom - top)
                bands.add(Triple(
                    max(0, (top - height).roundToInt()),
                    min(bitmap.height, (bottom + 2.2 * height).roundToInt()),
                    height,
                ))
            }
            if (bands.isEmpty()) bands.add(Triple((bitmap.height * .45).roundToInt(), bitmap.height, 0.0))
            for ((y0, y1, height) in bands) {
                checkCancellation(cancelled)
                if (y1 - y0 < 8) continue
                val wanted = if (height > 0) (64.0 / height).coerceIn(1.0, 3.0) else 1.5
                val area = bitmap.width.toLong() * (y1 - y0)
                val scale = min(wanted, sqrt(MAX_FOCUS_PIXELS.toDouble() / area)).coerceAtLeast(.5)
                val crop = Bitmap.createBitmap(bitmap, 0, y0, bitmap.width, y1 - y0)
                var scaled = crop
                try {
                    scaled = Bitmap.createScaledBitmap(
                        crop,
                        max(1, (crop.width * scale).roundToInt()),
                        max(1, (crop.height * scale).roundToInt()),
                        true,
                    )
                } finally {
                    if (scaled !== crop && crop !== bitmap) crop.recycle()
                }
                if (!scaled.isMutable) {
                    val copy = scaled.copy(Bitmap.Config.ARGB_8888, true)
                    if (scaled !== bitmap) scaled.recycle()
                    scaled = copy
                }
                try {
                    flattenIllumination(scaled)
                    engine.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK)
                    engine.setImage(scaled)
                    val text = engine.getUTF8Text() ?: ""
                    checkCancellation(cancelled)
                    for (row in text.lines()) {
                        val value = row.trim()
                        if (value.isEmpty()) continue
                        if (rows.size >= MAX_FOCUS_ROWS) return rows
                        rows.add(value.take(512))
                    }
                } finally {
                    if (scaled !== bitmap) scaled.recycle()
                }
            }
        } catch (failure: ReceiptOcrFailure) {
            if (failure.code == "OCR_CANCELLED") throw failure
            return emptyList()
        } catch (_: Exception) {
            return emptyList()
        } catch (_: OutOfMemoryError) {
            return emptyList()
        }
        return rows
    }

    /** OCR-tolerant total label: Latin look-alikes, one wrong letter. */
    private fun totalLike(text: String): Boolean {
        val words = text.split(Regex("\\s+"))
            .filter { word -> word.any { it.isLetter() } }
            .take(3)
            .map(::cyrillicLetters)
            .filter { it.isNotEmpty() }
        if (words.isEmpty()) return false
        val first = words[0]
        if (listOf("ИТОГ", "ИТОГО", "ВСЕГО").any { distance(first, it) <= 1 }) return true
        if (words.joinToString("").contains("КОПЛАТЕ")) return true
        return words.size > 1 && distance(words[0] + words[1], "ИТОГ") <= 1
    }

    private fun cyrillicLetters(word: String): String {
        val map = mapOf(
            'A' to 'А', 'B' to 'В', 'C' to 'С', 'E' to 'Е', 'H' to 'Н', 'K' to 'К', 'M' to 'М',
            'O' to 'О', 'P' to 'Р', 'T' to 'Т', 'X' to 'Х', 'Y' to 'У', 'N' to 'И', 'U' to 'И', 'W' to 'И',
            'R' to 'Г', 'F' to 'Г', '0' to 'О', 'Ё' to 'Е', 'Й' to 'И',
        )
        val out = StringBuilder()
        for (ch in word.uppercase()) {
            val mapped = map[ch] ?: ch
            if (mapped in 'А'..'Я') out.append(mapped)
        }
        return out.toString()
    }

    private fun distance(a: String, b: String): Int {
        var previous = IntArray(b.length + 1) { it }
        for (i in a.indices) {
            val current = IntArray(b.length + 1)
            current[0] = i + 1
            for (j in b.indices) {
                current[j + 1] = minOf(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + if (a[i] == b[j]) 0 else 1,
                )
            }
            previous = current
        }
        return previous[b.length]
    }

    /** Divides each pixel by a smooth estimate of the paper brightness
     * (3×3-smoothed maxima of blocks), removing shadows and fading on
     * receipt photos. Works row by row on a grayscale bitmap in place. */
    private fun flattenIllumination(bitmap: Bitmap) {
        val width = bitmap.width
        val height = bitmap.height
        if (width < 16 || height < 16) return
        val block = max(8, min(width, height) / 40)
        val columns = (width + block - 1) / block
        val rowsCount = (height + block - 1) / block
        val maxima = FloatArray(columns * rowsCount)
        val row = IntArray(width)
        for (y in 0 until height) {
            bitmap.getPixels(row, 0, width, 0, y, width, 1)
            val by = y / block
            for (x in 0 until width) {
                val value = (row[x] and 0xFF).toFloat()
                val index = by * columns + x / block
                if (value > maxima[index]) maxima[index] = value
            }
        }
        val smooth = FloatArray(maxima.size)
        for (by in 0 until rowsCount) for (bx in 0 until columns) {
            var sum = 0f
            for (dy in -1..1) for (dx in -1..1) {
                val yy = (by + dy).coerceIn(0, rowsCount - 1)
                val xx = (bx + dx).coerceIn(0, columns - 1)
                sum += maxima[yy * columns + xx]
            }
            smooth[by * columns + bx] = max(1f, sum / 9f)
        }
        for (y in 0 until height) {
            bitmap.getPixels(row, 0, width, 0, y, width, 1)
            val fy = ((y + .5f) / block - .5f).coerceIn(0f, (rowsCount - 1).toFloat())
            val y0 = fy.toInt()
            val y1 = min(rowsCount - 1, y0 + 1)
            val ty = fy - y0
            for (x in 0 until width) {
                val fx = ((x + .5f) / block - .5f).coerceIn(0f, (columns - 1).toFloat())
                val x0 = fx.toInt()
                val x1 = min(columns - 1, x0 + 1)
                val tx = fx - x0
                val top = smooth[y0 * columns + x0] * (1 - tx) + smooth[y0 * columns + x1] * tx
                val bottom = smooth[y1 * columns + x0] * (1 - tx) + smooth[y1 * columns + x1] * tx
                val background = top * (1 - ty) + bottom * ty
                val value = ((row[x] and 0xFF) * 255f / background).roundToInt().coerceIn(0, 255)
                row[x] = (0xFF shl 24) or (value shl 16) or (value shl 8) or value
            }
            bitmap.setPixels(row, 0, width, 0, y, width, 1)
        }
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
            // Shadows and faded thermal paper hide totals; flattening keeps
            // flat screenshots unchanged in practice. Optional on low memory.
            try {
                flattenIllumination(target)
            } catch (_: OutOfMemoryError) {
            }
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
