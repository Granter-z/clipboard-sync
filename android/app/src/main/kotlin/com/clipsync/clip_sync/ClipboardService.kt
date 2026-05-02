package com.clipsync.clip_sync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.net.HttpURLConnection
import java.net.URL

class ClipboardService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var clipboardManager: ClipboardManager? = null
    private var pollingTimer: java.util.Timer? = null
    private var prefs: SharedPreferences? = null

    companion object {
        @Volatile
        var suppressNextEvent = false

        @Volatile
        var lastClipboardText: String? = null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        val notification = createNotification()
        startForeground(1, notification)
        acquireWakeLock()
        prefs = getSharedPreferences("flutter", Context.MODE_PRIVATE)
        startPolling()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopPolling()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startPolling() {
        if (pollingTimer != null) return
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        pollingTimer = java.util.Timer()
        pollingTimer?.scheduleAtFixedRate(object : java.util.TimerTask() {
            override fun run() {
                checkClipboard()
            }
        }, 1000, 1000)
    }

    private fun stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = null
    }

    private fun checkClipboard() {
        if (suppressNextEvent) {
            suppressNextEvent = false
            return
        }

        try {
            val clipData = clipboardManager?.primaryClip ?: return
            if (clipData.itemCount == 0) return
            val item = clipData.getItemAt(0) ?: return

            if (item.text != null) {
                val text = item.text.toString().trim()
                if (text.isNotEmpty() && text != lastClipboardText) {
                    lastClipboardText = text
                    sendToRelay(text)
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun sendToRelay(text: String) {
        Thread {
            try {
                val relayUrl = prefs?.getString("relay_url", null) ?: return@Thread
                val deviceId = prefs?.getString("device_id", null) ?: return@Thread
                val deviceName = prefs?.getString("device_name", null) ?: "Android"

                // Convert ws:// to http:// for the POST endpoint
                val httpUrl = relayUrl
                    .replace("ws://", "http://")
                    .replace("wss://", "https://")
                    .trimEnd('/') + "/send"

                val hash = text.hashCode().toString(16).take(16)
                val json = """{"type":"clipboard_sync","version":1,"senderId":"$deviceId","senderName":"$deviceName","sequence":${System.currentTimeMillis()},"timestamp":${System.currentTimeMillis()},"payload":{"contentType":"text","data":${escapeJson(text)},"encoding":"utf-8","size":${text.length},"hash":"$hash"}}"""

                val url = URL(httpUrl)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 5000
                conn.readTimeout = 5000

                conn.outputStream.use { it.write(json.toByteArray()) }
                conn.responseCode // trigger the request
                conn.disconnect()
            } catch (_: Exception) {
            }
        }.start()
    }

    private fun escapeJson(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> sb.append(c)
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "clip_sync:wakelock")
        wakeLock?.acquire()
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "clip_sync_bg",
                "Clipboard Sync",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background clipboard sync service"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, "clip_sync_bg")
            .setContentTitle("Clipboard Sync")
            .setContentText("正在后台同步剪贴板")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
