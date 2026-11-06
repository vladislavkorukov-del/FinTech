package com.finora.fintech

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Developer check: runs the real native OCR engine (Tesseract4Android, JNI,
 * Android Bitmap) on images pushed to /data/local/tmp/finance-ocr and writes
 * the engine's response to the app's files/ocr-check directory.
 *   adb push img.jpg /data/local/tmp/finance-ocr/
 *   adb shell am instrument -w com.finora.fintech.test/androidx.test.runner.AndroidJUnitRunner
 *   adb shell run-as com.finora.fintech cat files/ocr-check/img.jpg.json
 */
@RunWith(AndroidJUnit4::class)
class ReceiptOcrDeviceCheck {
    @Test
    fun recognizePushedImages() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val ready = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationComplete(context, null)
            ready.countDown()
        }
        ready.await()
        val input = File("/data/local/tmp/finance-ocr")
        val output = File(context.filesDir, "ocr-check").apply { mkdirs() }
        val engine = ReceiptOcrEngine(context)
        for (source in input.listFiles().orEmpty().sortedBy { it.name }) {
            if (!source.isFile) continue
            val copy = File(context.filesDir, "ocr-input-${source.name}")
            source.copyTo(copy, overwrite = true)
            val started = System.nanoTime()
            val json = try {
                val result = engine.recognize(copy.path, AtomicBoolean(false))
                JSONObject().apply {
                    put("text", result["text"])
                    put("confidence", result["confidence"])
                    put("lines", JSONArray(result["lines"] as List<*>))
                    put("focus", JSONArray(result["focus"] as List<*>))
                    put("amounts", JSONArray(result["amounts"] as List<*>))
                }
            } catch (error: Throwable) {
                JSONObject().put("error", error.toString())
            }
            json.put("millis", (System.nanoTime() - started) / 1_000_000)
            File(output, "${source.name}.json").writeText(json.toString())
            copy.delete()
        }
    }
}
