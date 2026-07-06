package com.company.gateway

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val LOCATION_CHANNEL = "com.company.gateway/location_service"
    private val TELEMETRY_CHANNEL = "com.company.gateway/telemetry"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel 1: Location foreground service — start on login, stop on logout
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLocationService" -> {
                        // Start persistent notification when user logs in
                        LocationForegroundService.start(this)
                        result.success(null)
                    }
                    "stopLocationService" -> {
                        // Remove notification when user logs out
                        LocationForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Channel 2: Telemetry foreground service — start on login, stop on logout
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TELEMETRY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        // Start telemetry notification when user logs in
                        TelemetryForegroundService.start(this)
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        // Remove telemetry notification when user logs out
                        TelemetryForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
