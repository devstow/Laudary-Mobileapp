package com.example.mobileapp

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.work.Configuration
import android.app.Application
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Process-level safety net (added after builds 2013/2014 were installed on a phone and never started — 2026-10-29).
 *
 *  - A crash handler is installed in [attachBaseContext], i.e. BEFORE any ContentProvider / library initialiser runs,
 *    so even a crash during process start is captured. The stack trace is sent to the server right away
 *    (`POST api/public/app-release/android/report`, stage "crash") and kept in a file that the next start re-sends.
 *  - WorkManager is NOT auto-initialised at process start any more (manifest removes WorkManagerInitializer); it is
 *    created on demand through [Configuration.Provider] when background sync is first scheduled, inside try/catch.
 *  - The API URL comes from the build (`R.string.sw_api_base_url`, generated from the same --dart-define the Dart
 *    code uses), so a crash can be reported even if Dart never started.
 */
class SmartWashApplication : Application(), Configuration.Provider {

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setMinimumLoggingLevel(Log.WARN).build()

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val stack = Log.getStackTraceString(error).take(3500)
                crashFile(base).writeText(stack)
                // Best effort, max ~3 s: the process is about to die.
                val t = Thread { send(base, "crash", stack) }
                t.start(); t.join(3000)
            } catch (_: Throwable) { }
            previous?.uncaughtException(thread, error)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // A crash file left by the previous run (e.g. it died before the network call finished): send it now.
        val f = crashFile(this)
        if (f.exists()) {
            val stack = try { f.readText() } catch (_: Throwable) { "" }
            f.delete()
            Thread { send(this, "crashPreviousRun", stack) }.start()
        }
    }

    companion object {
        private fun crashFile(ctx: Context) = File(ctx.filesDir, "last-crash.txt")

        fun versionCode(ctx: Context): Long = try {
            val pi = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode else @Suppress("DEPRECATION") pi.versionCode.toLong()
        } catch (_: Throwable) { -1 }

        fun send(ctx: Context, stage: String, detail: String) {
            try {
                val base = ctx.getString(R.string.sw_api_base_url).trimEnd('/')
                if (base.isEmpty()) return
                val body = JSONObject()
                    .put("fromBuild", versionCode(ctx)).put("toBuild", versionCode(ctx)).put("stage", stage)
                    .put("detail", detail).put("sdk", Build.VERSION.SDK_INT)
                    .put("phase", "${Build.MANUFACTURER} ${Build.MODEL}".take(30))
                val c = (URL("$base/api/public/app-release/android/report").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"; doOutput = true; connectTimeout = 2500; readTimeout = 2500
                    setRequestProperty("Content-Type", "application/json")
                }
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                c.responseCode
                c.disconnect()
            } catch (_: Throwable) { }
        }
    }
}
