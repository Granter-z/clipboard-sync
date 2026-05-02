package com.clipsync.clip_sync

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.net.wifi.WifiManager
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.clipsync/clipboard"

    private var clipboardManager: ClipboardManager? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeText" -> {
                        val text = call.argument<String>("text") ?: ""
                        writeToClipboard(text)
                        result.success(true)
                    }
                    "readText" -> {
                        result.success(readFromClipboard())
                    }
                    "readImage" -> {
                        result.success(readImageFromClipboard())
                    }
                    "writeImage" -> {
                        val base64 = call.argument<String>("data") ?: ""
                        writeImageToClipboard(base64)
                        result.success(true)
                    }
                    "startMonitoring" -> {
                        startClipboardMonitoring()
                        result.success(true)
                    }
                    "stopMonitoring" -> {
                        stopClipboardMonitoring()
                        result.success(true)
                    }
                    "acquireMulticastLock" -> {
                        acquireMulticastLock()
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startClipboardMonitoring() {
        val serviceIntent = Intent(this, ClipboardService::class.java)
        startForegroundService(serviceIntent)
    }

    private fun stopClipboardMonitoring() {
        stopService(Intent(this, ClipboardService::class.java))
    }

    private fun acquireMulticastLock() {
        if (multicastLock != null) return
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("clipSyncDiscovery")
        multicastLock?.setReferenceCounted(true)
        multicastLock?.acquire()
    }

    private fun releaseMulticastLock() {
        multicastLock?.release()
        multicastLock = null
    }

    private fun writeToClipboard(text: String) {
        ClipboardService.suppressNextEvent = true
        ClipboardService.lastClipboardText = text.trim()
        val clipData = ClipData.newPlainText("clip_sync", text)
        clipboardManager?.setPrimaryClip(clipData)
        android.os.Handler(mainLooper).postDelayed({
            ClipboardService.suppressNextEvent = false
        }, 2000)
    }

    private fun readFromClipboard(): String? {
        return clipboardManager?.primaryClip?.getItemAt(0)?.text?.toString()
    }

    private fun readImageFromClipboard(): String? {
        return try {
            val clipData = clipboardManager?.primaryClip ?: return null
            val item = clipData.getItemAt(0) ?: return null

            if (item.uri != null) {
                val bitmap = contentResolver.openInputStream(item.uri)?.use { stream ->
                    BitmapFactory.decodeStream(stream)
                }
                if (bitmap != null) {
                    val stream = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    val byteArray = stream.toByteArray()
                    val base64 = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                    bitmap.recycle()
                    return base64
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    private fun writeImageToClipboard(base64Data: String) {
        try {
            val byteArray = Base64.decode(base64Data, Base64.NO_WRAP)
            val bitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) ?: return

            val cacheDir = File(cacheDir, "clipboard")
            if (!cacheDir.exists()) cacheDir.mkdirs()

            val imageFile = File(cacheDir, "clipboard_image.png")
            imageFile.outputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            }
            bitmap.recycle()

            val authority = "${packageName}.fileprovider"
            val contentUri: Uri = FileProvider.getUriForFile(this, authority, imageFile)

            ClipboardService.suppressNextEvent = true
            val clipData = ClipData.newUri(contentResolver, "clip_sync_image", contentUri)
            clipboardManager?.setPrimaryClip(clipData)
            android.os.Handler(mainLooper).postDelayed({
                ClipboardService.suppressNextEvent = false
            }, 2000)
        } catch (e: Exception) {
            // Error writing image to clipboard
        }
    }
}
