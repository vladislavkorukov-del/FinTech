package com.finora.fintech

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import android.content.Intent
import android.os.Bundle
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    private var receiptOcr: ReceiptOcrBridge? = null
    private var receiptShare: ReceiptShareBridge? = null
    private var voiceInput: VoiceInputBridge? = null
    private var dispatchedShareIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dispatchShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Screenshots are explicitly allowed by the user. The app PIN still guards entry.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        receiptOcr?.close()
        receiptOcr = ReceiptOcrBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        receiptShare?.close()
        receiptShare = ReceiptShareBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        voiceInput?.close()
        voiceInput = VoiceInputBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // FlutterFragment may attach after Activity.onCreate has returned.
        // Dispatch here too, once per Intent, so cold-start shares cannot vanish.
        dispatchShareIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finora/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "timeZone" -> result.success(TimeZone.getDefault().id)
                    else -> result.notImplemented()
                }
            }
    }

    private fun dispatchShareIntent(value: Intent?) {
        if (value == null || value === dispatchedShareIntent) return
        val bridge = receiptShare ?: return
        dispatchedShareIntent = value
        bridge.accept(value)
    }

    @Deprecated("Speech dialog result")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (voiceInput?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        voiceInput?.close()
        voiceInput = null
        receiptOcr?.close()
        receiptOcr = null
        receiptShare?.close()
        receiptShare = null
        super.onDestroy()
    }
}
