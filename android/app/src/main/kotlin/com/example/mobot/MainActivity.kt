package com.example.mobot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mo/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "startWake" -> {
                    try {
                        WakeService.start(
                            applicationContext,
                            call.argument<String>("wake") ?: "",
                            call.argument<String>("locale") ?: "en-US"
                        )
                        result.success(true)
                    } catch (t: Throwable) {
                        result.success(false)
                    }
                }
                "stopWake" -> {
                    try { WakeService.stop(applicationContext) } catch (_: Throwable) {}
                    result.success(true)
                }
                "consumeWake" -> {
                    val t = WakeService.consume()
                    result.success(if (t == null) null else mapOf("text" to t))
                }
                "getVoices" -> VoiceTools.list(applicationContext) { result.success(it) }
                "classifyVoices" -> {
                    val names = call.argument<List<String>>("names") ?: emptyList()
                    VoiceTools.classify(applicationContext, names) { result.success(it) }
                }
                else -> result.notImplemented()
            }
        }
    }

    // While MO is on screen, Flutter owns the microphone; otherwise the wake service does.
    override fun onResume() {
        super.onResume()
        WakeService.setVisible(true)
    }

    override fun onPause() {
        super.onPause()
        WakeService.setVisible(false)
    }
}
