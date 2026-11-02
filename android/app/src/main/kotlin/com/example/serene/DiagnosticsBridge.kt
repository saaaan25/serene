package com.example.serene

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DiagnosticsBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private var previousCpu: Long? = null
    private var previousWall: Long? = null

    init {
        MethodChannel(messenger, "com.example.serene/diagnostics").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "begin" -> {
                        previousCpu = Process.getElapsedCpuTime()
                        previousWall = SystemClock.elapsedRealtime()
                        result.success(null)
                    }
                    "end" -> {
                        previousCpu = null
                        previousWall = null
                        result.success(null)
                    }
                    "sample" -> result.success(sample())
                    "share" -> {
                        val json = call.argument<String>("json")
                        require(json != null && json.length <= 2_000_000)
                        share(json)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("diagnostics_unavailable", "Could not complete the diagnostic operation", null)
            }
        }
    }

    private fun sample(): Map<String, Any> {
        val cpu = Process.getElapsedCpuTime()
        val wall = SystemClock.elapsedRealtime()
        val memory = Debug.MemoryInfo()
        Debug.getMemoryInfo(memory)
        val data = mutableMapOf<String, Any>(
            "process_pss_bytes" to memory.totalPss.toLong() * 1024,
            "device_model" to Build.MODEL,
            "platform_version" to Build.VERSION.RELEASE,
        )
        val elapsed = previousWall?.let { wall - it }
        val used = previousCpu?.let { cpu - it }
        if (elapsed != null && elapsed >= 250 && used != null && used >= 0) {
            data["process_cpu_percent_one_core"] = 100.0 * used / elapsed
        }
        previousCpu = cpu
        previousWall = wall
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level >= 0 && scale > 0) data["battery_percent"] = 100.0 * level / scale
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
        if (plugged >= 0) data["charging"] = plugged != 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val power = activity.getSystemService(PowerManager::class.java)
            data["thermal_state"] = when (power?.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE -> "none"
                PowerManager.THERMAL_STATUS_LIGHT -> "light"
                PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
                PowerManager.THERMAL_STATUS_SEVERE -> "severe"
                PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
                PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
                PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
                else -> "unknown"
            }
        }
        return data
    }

    private fun share(json: String) {
        val directory = File(activity.cacheDir, "diagnostics")
        check(directory.isDirectory || directory.mkdirs())
        val expiry = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        directory.listFiles()?.filter {
            it.isFile && it.name.startsWith("serene_diagnostics_") && it.extension == "json" && it.lastModified() < expiry
        }?.forEach { it.delete() }
        val report = File(directory, "serene_diagnostics_${System.currentTimeMillis()}.json")
        report.writeText(json, Charsets.UTF_8)
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.diagnostics", report)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("Serene diagnostics", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(intent, null))
    }
}
