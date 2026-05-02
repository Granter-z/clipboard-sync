package com.clipsync.clip_sync

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.clipsync/clipboard"
    private val EVENT_CHANNEL = "com.clipsync/clipboard/events"
    
    private var clipboardManager: ClipboardManager? = null
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        // Method Channel for read/write
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
                    else -> result.notImplemented()
                }
            }

        // Event Channel for push-based clipboard changes
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun startClipboardMonitoring() {
        if (clipboardListener != null) return

        clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
            try {
                val clipData = clipboardManager?.primaryClip ?: return@OnPrimaryClipChangedListener
                val item = clipData.getItemAt(0) ?: return@OnPrimaryClipChangedListener

                if (item.text != null) {
                    eventSink?.success(mapOf(
                        "type" to "text",
                        "data" to item.text.toString()
                    ))
                } else if (item.uri != null) {
                    try {
                        val bitmap = contentResolver.openInputStream(item.uri)?.use { stream ->
                            BitmapFactory.decodeStream(stream)
                        }
                        if (bitmap != null) {
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            val byteArray = stream.toByteArray()
                            val base64 = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                            bitmap.recycle()
                            eventSink?.success(mapOf(
                                "type" to "image",
                                "data" to base64
                            ))
                        }
                    } catch (e: Exception) {
                        // Error decoding image from URI
                    }
                }
            } catch (e: Exception) {
                // Clipboard monitoring error
            }
        }

        clipboardListener?.let { listener ->
            clipboardManager?.addPrimaryClipChangedListener(listener)
        }
    }

    private fun stopClipboardMonitoring() {
        clipboardListener?.let { listener ->
            clipboardManager?.removePrimaryClipChangedListener(listener)
        }
        clipboardListener = null
    }

    private fun writeToClipboard(text: String) {
        val clipData = ClipData.newPlainText("clip_sync", text)
        clipboardManager?.setPrimaryClip(clipData)
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
            val bitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size)
            if (bitmap != null) {
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                val clipData = ClipData.newRawUri("clip_sync_image", 
                    android.net.Uri.parse("content://clip_sync/image"))
                clipboardManager?.setPrimaryClip(clipData)
                bitmap.recycle()
            }
        } catch (e: Exception) {
            // Error writing image to clipboard
        }
    }
}
