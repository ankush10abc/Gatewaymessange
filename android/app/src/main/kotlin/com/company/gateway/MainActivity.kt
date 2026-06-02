package com.company.gateway

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Bundle

class MainActivity : FlutterActivity() {
//    private val CHANNEL = "com.company.gateway/telemetry"
//
//    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//        super.configureFlutterEngine(flutterEngine)
//        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
//            when (call.method) {
//                "startForegroundService" -> {
//                    val userId = call.argument<String>("userId") ?: ""
//                    val authToken = call.argument<String>("authToken") ?: ""
//                    TelemetryForegroundService.startService(this, userId, authToken)
//                    result.success(null)
//                }
//                "stopForegroundService" -> {
//                    TelemetryForegroundService.stopService(this)
//                    result.success(null)
//                }
//                else -> result.notImplemented()
//            }
//        }
//    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
//        handleIntent(intent)
    }

//    override fun onNewIntent(intent: Intent) {
//        super.onNewIntent(intent)
//        handleIntent(intent)
//    }

//    private fun handleIntent(intent: Intent?) {
//        if (intent?.action == Intent.ACTION_VIEW) {
//            setIntent(intent)
//        }
//    }
}
