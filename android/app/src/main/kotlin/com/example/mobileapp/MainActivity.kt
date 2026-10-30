package com.example.mobileapp

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native helpers behind `lib/core/downloads.dart` (channel `smartwash/downloads`):
 *  - saveToDownloads(name, mime, bytes) → writes the file into the public Downloads/SmartWash folder
 *    (MediaStore on Android 10+, so no storage permission is needed; app-scoped external storage on
 *    Android 7–9) and returns {uri, path}.
 *  - openFile(uri, mime) → opens that URI in the app that handles the MIME type (PDF viewer) with a
 *    read grant. Returns false when no viewer is installed — the file is still saved.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "smartwash/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name") ?: "download.bin"
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        result.success(saveToDownloads(name, mime, bytes))
                    }
                    "openFile" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        val mime = call.argument<String>("mime") ?: "*/*"
                        result.success(openFile(uri, mime))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("downloads", e.message ?: e.javaClass.simpleName, null)
            }
        }

        // Unread badge, system notifications, background sync (see AppNotifications.kt). A tapped notification
        // opens the app with EXTRA_OPEN; Dart asks for it once at start (launchTarget) and gets "open" later.
        val notifyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartwash/notify")
        this.notifyChannel = notifyChannel
        notifyChannel.setMethodCallHandler { call, result ->
            try {
                if (call.method == "launchTarget") {
                    result.success(pendingOpen)
                    pendingOpen = null
                } else {
                    @Suppress("UNCHECKED_CAST")
                    AppNotifications.handle(this, call.method, (call.arguments as? Map<String, Any?>) ?: emptyMap(), result)
                }
            } catch (e: Exception) {
                result.error("notify", e.message ?: e.javaClass.simpleName, null)
            }
        }

        // In-app updates (see AppUpdater.kt).
        val updaterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartwash/updater")
        val updater = AppUpdater(this, updaterChannel)
        AppUpdater.current = updater
        updaterChannel.setMethodCallHandler { call, result ->
            try {
                @Suppress("UNCHECKED_CAST")
                updater.handle(call.method, (call.arguments as? Map<String, Any?>) ?: emptyMap(), result)
            } catch (e: Exception) {
                result.error("updater", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private var notifyChannel: MethodChannel? = null
    private var pendingOpen: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        pendingOpen = intent?.getStringExtra(AppNotifications.EXTRA_OPEN)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val target = intent.getStringExtra(AppNotifications.EXTRA_OPEN) ?: return
        val ch = notifyChannel
        if (ch != null) ch.invokeMethod("open", target) else pendingOpen = target
    }

    override fun onResume() {
        super.onResume()
        AppUpdater.current?.resumed = true
    }

    override fun onPause() {
        AppUpdater.current?.resumed = false
        super.onPause()
    }

    @Deprecated("Activity result of the system package installer (AppUpdater)")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (AppUpdater.current?.onActivityResult(requestCode, resultCode) != true) super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        if (isFinishing) AppUpdater.current = null
        super.onDestroy()
    }

    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SmartWash")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create the download entry")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not write the download")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return mapOf("uri" to uri.toString(), "path" to "${Environment.DIRECTORY_DOWNLOADS}/SmartWash/$name")
        }
        // Android 7–9: app-scoped external Downloads (no runtime permission), shared through FileProvider.
        val dir = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "SmartWash").apply { mkdirs() }
        val file = File(dir, name)
        file.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        return mapOf("uri" to uri.toString(), "path" to file.absolutePath)
    }

    private fun openFile(uri: Uri, mime: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
