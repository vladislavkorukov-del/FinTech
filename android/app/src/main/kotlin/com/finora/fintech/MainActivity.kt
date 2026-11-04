package com.finora.fintech

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Screenshots are explicitly allowed by the user. The app PIN still guards entry.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finora/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "timeZone" -> result.success(TimeZone.getDefault().id)
                    else -> result.notImplemented()
                }
            }
    }
}
