package com.example.mobileapp

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Native half of the in-app updater (`lib/features/update/native_updater.dart`, channel `smartwash/updater`).
 * Uses only what Android allows a sideloaded app to do — nothing is installed silently:
 *  - info              → installed package/versionCode/signing certificate, install permission, cache dir, free space
 *  - openInstallSettings → "Install unknown apps" screen for this app (Android 8+), the user decides
 *  - verify(path, sha256, versionCode) → checksum, package name, version, minSdk and SAME signing certificate as the
 *                        installed app — a file that fails any of these is never handed to the installer
 *  - install(path)     → hands the verified file to Android's installer (Android always asks the user to confirm a
 *                        sideloaded update — nothing is installed silently):
 *      · Android ≤ 11: the system package installer screen, launched FROM THE VISIBLE ACTIVITY ("Update this app?" →
 *        Install → "App installed" → Open, which relaunches the new version). Returning without the app being
 *        replaced = cancelled / failed (reported as `installerClosed`).
 *      · Android 12+: a PackageInstaller session (the app becomes the installer of record, so Android may let later
 *        updates through without a prompt). Its confirmation is started from the visible activity — 2026-10-29 a
 *        phone downloaded the update and then nothing appeared, because the confirmation was started from a
 *        background broadcast receiver, which many ROMs block. If no confirmation shows within 12 s the standard
 *        installer screen is used instead (`fallbackInstaller`).
 *    Every outcome comes back as `installStatus` (installerOpened / pendingUserAction / success / aborted /
 *    installerClosed / fallbackInstaller / failure codes).
 * After an update Android does not reopen the app by itself (except the installer's Open button):
 * [PackageReplacedReceiver] posts a "tap to open" notification, and the app restores the screen the user was on.
 */
class AppUpdater(private val activity: Activity, private val channel: MethodChannel) {

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        when (method) {
            "info" -> result.success(info())
            "openInstallSettings" -> result.success(openInstallSettings())
            "verify" -> result.success(verify(args["path"] as String, args["sha256"] as String?, (args["versionCode"] as Number?)?.toLong()))
            "install" -> result.success(install(args["path"] as String, args["mode"] as String?))
            else -> result.notImplemented()
        }
    }

    private fun installedInfo(): PackageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
    else @Suppress("DEPRECATION") activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNATURES)

    private fun info(): Map<String, Any?> {
        val pi = installedInfo()
        val cache = File(activity.cacheDir, "updates").apply { mkdirs() }
        return mapOf(
            "packageName" to activity.packageName,
            "versionCode" to versionCode(pi),
            "versionName" to pi.versionName,
            "certSha256" to certs(pi).firstOrNull(),
            "sdk" to Build.VERSION.SDK_INT,
            "canInstall" to canInstall(),
            "cacheDir" to cache.absolutePath,
            "freeBytes" to cache.usableSpace,
        )
    }

    private fun canInstall(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
        activity.packageManager.canRequestPackageInstalls()
    else @Suppress("DEPRECATION") (Settings.Secure.getInt(activity.contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1)

    private fun openInstallSettings(): Boolean = try {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
        else Intent(Settings.ACTION_SECURITY_SETTINGS)
        activity.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun verify(path: String, sha256: String?, expectedCode: Long?): Map<String, Any?> {
        fun fail(code: String, message: String) = mapOf("ok" to false, "code" to code, "message" to message)
        val file = File(path)
        if (!file.isFile || file.length() == 0L) return fail("missing", "The downloaded file is missing or empty.")
        if (sha256.isNullOrBlank()) return fail("checksum", "The release has no checksum to verify against.")
        val actual = sha256Of(file)
        if (!actual.equals(sha256, ignoreCase = true)) return fail("checksum", "Checksum mismatch: the download is incomplete or not the published file.")

        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(path, flags) ?: return fail("invalid", "The downloaded file is not a valid Android package.")
        if (archive.packageName != activity.packageName)
            return fail("package", "The update is for a different app (${archive.packageName}).")
        val installed = installedInfo()
        val newCode = versionCode(archive)
        if (expectedCode != null && newCode != expectedCode) return fail("version", "The file is build $newCode, the release says $expectedCode.")
        if (newCode <= versionCode(installed)) return fail("version", "The file (build $newCode) is not newer than the installed app (build ${versionCode(installed)}).")
        val minSdk = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) archive.applicationInfo?.minSdkVersion ?: 0 else 0
        if (minSdk > Build.VERSION.SDK_INT) return fail("incompatible", "This update needs Android API $minSdk; the phone has API ${Build.VERSION.SDK_INT}.")

        // Same signer as the installed app, or Android refuses the update ("App not installed").
        val mine = certs(installed).toSet()
        val theirs = certs(archive)
        if (theirs.isNotEmpty() && theirs.none { it in mine })
            return fail("signature", "The update is signed with a different certificate than the installed app.")
        return mapOf("ok" to true, "versionCode" to newCode, "versionName" to archive.versionName, "sha256" to actual,
            "certChecked" to theirs.isNotEmpty())
    }

    private val main = Handler(Looper.getMainLooper())
    private var watchdog: Runnable? = null
    private var sessionPath: String? = null
    @Volatile var resumed = true

    /** Returns the mechanism used: "installer" (system installer screen) or "session". */
    private fun install(path: String, mode: String?): String {
        val useSession = mode == "session" || (mode == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
        return if (useSession) { installSession(path); "session" } else { installIntent(path); "installer" }
    }

    /** The system package installer screen (works on every Android version / ROM). */
    private fun installIntent(path: String) {
        cancelWatchdog()
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", File(path))
        @Suppress("DEPRECATION")
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, activity.packageName)
        }
        activity.startActivityForResult(intent, REQUEST_INSTALL)
        report("installerOpened", null, 0)
    }

    private fun installSession(path: String) {
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(activity.packageName)
            // Android 12+: no prompt when this app is already the installer of record (after one session update).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            val file = File(path)
            file.inputStream().use { input ->
                session.openWrite("smartwash.apk", 0, file.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = Intent(activity, InstallResultReceiver::class.java).setPackage(activity.packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(activity, sessionId, intent, flags)
            sessionPath = path
            // Nothing from the installer within 12 s (ROM swallowed the confirmation) → the standard installer screen.
            watchdog = Runnable {
                watchdog = null
                report("fallbackInstaller", "No installer confirmation appeared", 0)
                try { installIntent(path) } catch (e: Exception) { report("failure", e.message, -1) }
            }.also { main.postDelayed(it, 12_000) }
            session.commit(pending.intentSender)
        }
    }

    private fun cancelWatchdog() { watchdog?.let { main.removeCallbacks(it) }; watchdog = null }

    /** Session needs the user's confirmation: show it from the visible activity, or as a notification otherwise. */
    fun confirm(confirmIntent: Intent) {
        cancelWatchdog()
        activity.runOnUiThread {
            try {
                if (resumed) {
                    activity.startActivity(confirmIntent)
                    report("pendingUserAction", null, 0)
                } else {
                    notifyConfirm(activity, confirmIntent)
                    report("pendingUserAction", "notification", 0)
                }
            } catch (e: Exception) {
                val p = sessionPath
                if (p != null) { report("fallbackInstaller", e.message, 0); installIntent(p) } else report("failure", e.message, -1)
            }
        }
    }

    fun onSessionResult(status: String, message: String?, code: Int) { cancelWatchdog(); report(status, message, code) }

    /** The system installer screen closed and this process is still running the old version → not installed. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_INSTALL) return false
        report("installerClosed", if (resultCode == Activity.RESULT_OK) "ok" else "cancelled", resultCode)
        return true
    }

    fun report(status: String, message: String?, code: Int) {
        activity.runOnUiThread { channel.invokeMethod("installStatus", mapOf("status" to status, "message" to message, "code" to code)) }
    }

    companion object {
        /** The running activity's updater, so the result receiver can report back to Dart (null = app not open). */
        @Volatile var current: AppUpdater? = null
        const val REQUEST_INSTALL = 7201

        /** App not in the foreground when Android asks for confirmation: a notification opens the confirmation. */
        fun notifyConfirm(context: Context, confirm: Intent) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                nm.createNotificationChannel(NotificationChannel("app_update", "App updates", NotificationManager.IMPORTANCE_HIGH))
            val pi = PendingIntent.getActivity(context, 7202, confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(context, "app_update")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Smart Wash update ready")
                .setContentText("Tap to install the downloaded update.")
                .setContentIntent(pi).setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH).build()
            try { nm.notify(7002, n) } catch (e: SecurityException) { }
        }

        fun versionCode(pi: PackageInfo): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode else @Suppress("DEPRECATION") pi.versionCode.toLong()

        fun certs(pi: PackageInfo): List<String> {
            val sigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pi.signingInfo ?: return emptyList()
                if (info.hasMultipleSigners()) info.apkContentsSigners else info.signingCertificateHistory
            } else @Suppress("DEPRECATION") pi.signatures
            return sigs?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) } ?: emptyList()
        }

        fun sha256Of(file: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) { val n = input.read(buf); if (n <= 0) break; md.update(buf, 0, n) }
            }
            return hex(md.digest())
        }

        private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    }
}

/** PackageInstaller session results. PENDING_USER_ACTION → show Android's own confirmation dialog. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val updater = AppUpdater.current
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java) else intent.getParcelableExtra(Intent.EXTRA_INTENT))
                ?: return updater?.onSessionResult("failure", "No confirmation intent", status) ?: Unit
            if (updater != null) updater.confirm(confirm) else AppUpdater.notifyConfirm(context, confirm)
            return
        }
        val name = when (status) {
            PackageInstaller.STATUS_SUCCESS -> "success"
            PackageInstaller.STATUS_FAILURE_ABORTED -> "aborted"
            PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
            PackageInstaller.STATUS_FAILURE_CONFLICT -> "conflict"
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "incompatible"
            PackageInstaller.STATUS_FAILURE_INVALID -> "invalid"
            PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
            else -> "failure"
        }
        updater?.onSessionResult(name, message, status)
    }
}

/** Sent by Android to the NEW version right after it replaced the old one. Android does not reopen an updated app
 *  and blocks background activity starts, so a notification offers to open it (the app then restores the screen). */
class PackageReplacedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            nm.createNotificationChannel(NotificationChannel("app_update", "App updates", NotificationManager.IMPORTANCE_HIGH))
        val pi = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val version = try { context.packageManager.getPackageInfo(context.packageName, 0).versionName } catch (e: Exception) { null }
        val n = NotificationCompat.Builder(context, "app_update")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Smart Wash updated" + (version?.let { " to $it" } ?: ""))
            .setContentText("Tap to open the app and continue where you left off.")
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        try { nm.notify(7001, n) } catch (e: SecurityException) { /* notifications not allowed — the user opens the app from the launcher */ }
    }
}
