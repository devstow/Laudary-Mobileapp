package com.example.mobileapp

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Unread-notification badge + system notifications (channel `smartwash/notify`, Dart: lib/features/notifications/
 * notification_center.dart). The NUMBER always comes from the server (authoritative unread count of the signed-in
 * user), never from counting pushes locally.
 *
 * Launcher badge: Android has no public "set badge number" API. Launchers derive the badge from the app's active
 * notifications — Android 8+ shows a dot (Pixel / stock) or a number (Samsung One UI, many others) taken from the
 * notification's `setNumber`. So the badge is carried by ONE summary notification ("You have N unread notifications",
 * number = N) that is updated in place and removed at 0. Older Samsung/LG/Sony launchers also get the legacy
 * BADGE_COUNT_UPDATE broadcast. Numeric vs dot vs nothing depends on the launcher — not controllable by the app.
 *
 * App closed: [BadgeSyncWorker] (WorkManager, every 15 min = Android's minimum, network required, Doze may delay it)
 * reads `api/notifications/devices/summary` with this install's DEVICE TOKEN (revoked at sign-out, dead once the
 * user has no live session) and updates the badge + posts new unread notifications. Instant delivery to a closed app
 * would need a push service (FCM), which is not configured.
 */
object AppNotifications {
    private const val TAG = "SmartWashNotify"
    private const val PREFS = "sw_notify"
    private const val CH_ALERTS = "sw_alerts"
    private const val CH_BADGE = "sw_unread"
    private const val GROUP = "sw_notifications"
    private const val SUMMARY_ID = 7100
    private const val WORK = "sw-badge-sync"
    const val EXTRA_OPEN = "sw_open"

    fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun channels(ctx: Context, lang: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ar = lang == "ar"
        nm.createNotificationChannel(NotificationChannel(CH_ALERTS, if (ar) "الإشعارات" else "Notifications", NotificationManager.IMPORTANCE_HIGH).apply {
            setShowBadge(true)
        })
        nm.createNotificationChannel(NotificationChannel(CH_BADGE, if (ar) "عدد الإشعارات غير المقروءة" else "Unread count", NotificationManager.IMPORTANCE_MIN).apply {
            setShowBadge(true)
            setSound(null, null)
            enableVibration(false)
        })
    }

    private fun openIntent(ctx: Context, target: String, requestCode: Int): PendingIntent {
        val launch = (ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent()).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_OPEN, target)
        }
        return PendingIntent.getActivity(ctx, requestCode, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun canNotify(ctx: Context) = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Badge = the server's unread count. 0 removes the summary (and our alerts: nothing unread is left to show). */
    fun setBadge(ctx: Context, count: Int) {
        val p = prefs(ctx)
        val lang = p.getString("lang", "en") ?: "en"
        p.edit().putInt("count", count).apply()
        val nm = NotificationManagerCompat.from(ctx)
        legacyBadgeBroadcast(ctx, count)
        if (count <= 0) {
            nm.cancel(SUMMARY_ID)
            for (id in p.getStringSet("posted", emptySet()) ?: emptySet()) nm.cancel(id.toIntOrNull() ?: continue)
            p.edit().putStringSet("posted", emptySet()).apply()
            return
        }
        if (!canNotify(ctx)) return
        channels(ctx, lang)
        val ar = lang == "ar"
        val text = if (ar) "لديك $count ${if (count == 1) "إشعار غير مقروء" else "إشعارات غير مقروءة"}" else "You have $count unread notification${if (count == 1) "" else "s"}"
        val n = NotificationCompat.Builder(ctx, CH_BADGE)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Smart Wash")
            .setContentText(text)
            .setNumber(count)
            .setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
            .setGroup(GROUP)
            .setGroupSummary(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openIntent(ctx, "notifications", SUMMARY_ID))
            .setAutoCancel(false)
            .build()
        try { nm.notify(SUMMARY_ID, n) } catch (e: SecurityException) { Log.w(TAG, "badge not shown: ${e.message}") }
    }

    /** Posts unread notifications the user has not been shown yet (each id once), newest last. */
    fun showItems(ctx: Context, items: JSONArray) {
        val p = prefs(ctx)
        val lang = p.getString("lang", "en") ?: "en"
        if (!canNotify(ctx)) return
        channels(ctx, lang)
        val seen = (p.getStringSet("notified", emptySet()) ?: emptySet()).toMutableSet()
        val posted = (p.getStringSet("posted", emptySet()) ?: emptySet()).toMutableSet()
        val nm = NotificationManagerCompat.from(ctx)
        for (i in items.length() - 1 downTo 0) {
            val o = items.optJSONObject(i) ?: continue
            val id = o.optString("id")
            if (id.isEmpty() || o.optBoolean("isRead") || id in seen) continue
            val nid = (id.hashCode() and 0x7fffffff) % 1_000_000 + 10_000
            val n = NotificationCompat.Builder(ctx, CH_ALERTS)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(o.optString("title"))
                .setContentText(o.optString("body"))
                .setStyle(NotificationCompat.BigTextStyle().bigText(o.optString("body")))
                .setGroup(GROUP)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(openIntent(ctx, "notification:$id", nid))
                .build()
            try { nm.notify(nid, n); posted.add(nid.toString()) } catch (e: SecurityException) { Log.w(TAG, "notification not shown: ${e.message}") }
            seen.add(id)
        }
        // keep the de-duplication set bounded
        val trimmed = if (seen.size > 300) seen.toList().takeLast(300).toSet() else seen
        p.edit().putStringSet("notified", trimmed).putStringSet("posted", posted).apply()
    }

    /** Marks ids as already shown (the app was open when they arrived — no system notification needed later). */
    fun markSeen(ctx: Context, ids: List<String>) {
        val p = prefs(ctx)
        val seen = (p.getStringSet("notified", emptySet()) ?: emptySet()).toMutableSet()
        seen.addAll(ids)
        p.edit().putStringSet("notified", if (seen.size > 300) seen.toList().takeLast(300).toSet() else seen).apply()
    }

    private fun legacyBadgeBroadcast(ctx: Context, count: Int) {
        try {
            val cls = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.component?.className ?: return
            ctx.sendBroadcast(Intent("android.intent.action.BADGE_COUNT_UPDATE").apply {
                putExtra("badge_count", count)
                putExtra("badge_count_package_name", ctx.packageName)
                putExtra("badge_count_class_name", cls)
            })
        } catch (e: Exception) { /* launcher without legacy badge support */ }
    }

    /** Signed in: remember what the background job needs and schedule it. */
    fun configure(ctx: Context, deviceToken: String, userId: String, apiBase: String, lang: String) {
        prefs(ctx).edit().putString("deviceToken", deviceToken).putString("userId", userId).putString("apiBase", apiBase).putString("lang", lang).apply()
        val req = PeriodicWorkRequestBuilder<BadgeSyncWorker>(15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        // Optional feature: a background-sync failure must never affect the app itself.
        try { WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, req) } catch (e: Throwable) { Log.w(TAG, "background sync not scheduled: ${e.message}") }
    }

    fun setLanguage(ctx: Context, lang: String) = prefs(ctx).edit().putString("lang", lang).apply()

    /** Signed out: stop the job, forget the device token, remove badge + notifications of the previous user. */
    fun clearSession(ctx: Context) {
        try { WorkManager.getInstance(ctx).cancelUniqueWork(WORK) } catch (e: Throwable) { Log.w(TAG, "background sync not cancelled: ${e.message}") }
        setBadge(ctx, 0)
        NotificationManagerCompat.from(ctx).cancelAll()
        val lang = prefs(ctx).getString("lang", "en")
        prefs(ctx).edit().clear().putString("lang", lang).apply()
    }

    fun handle(activity: Activity, method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        val ctx = activity.applicationContext
        when (method) {
            "configure" -> { configure(ctx, args["deviceToken"] as String, args["userId"] as String, args["apiBase"] as String, (args["lang"] as String?) ?: "en"); result.success(true) }
            "session" -> result.success(mapOf("deviceToken" to prefs(ctx).getString("deviceToken", null), "userId" to prefs(ctx).getString("userId", null)))
            "setLanguage" -> { setLanguage(ctx, (args["lang"] as String?) ?: "en"); result.success(true) }
            "clearSession" -> { clearSession(ctx); result.success(true) }
            "setBadge" -> { setBadge(ctx, (args["count"] as Number).toInt()); result.success(true) }
            "showItems" -> { showItems(ctx, JSONArray(args["items"] as String)); result.success(true) }
            "markSeen" -> { @Suppress("UNCHECKED_CAST") markSeen(ctx, (args["ids"] as List<String>?) ?: emptyList()); result.success(true) }
            "permission" -> result.success(canNotify(ctx))
            "requestPermission" -> {
                if (Build.VERSION.SDK_INT >= 33 && !canNotify(ctx)) ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7101)
                result.success(canNotify(ctx))
            }
            else -> result.notImplemented()
        }
    }
}

/** Background badge sync while the app is closed (see [AppNotifications]). */
class BadgeSyncWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val p = AppNotifications.prefs(applicationContext)
        val token = p.getString("deviceToken", null) ?: return Result.success()
        val base = p.getString("apiBase", null) ?: return Result.success()
        val lang = p.getString("lang", "en") ?: "en"
        return try {
            val conn = (URL("$base/api/notifications/devices/summary?take=5").openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 20000
                setRequestProperty("X-Device-Token", token)
                setRequestProperty("Accept-Language", lang)
            }
            when (conn.responseCode) {
                200 -> {
                    val body = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
                    AppNotifications.showItems(applicationContext, body.optJSONArray("unread") ?: JSONArray())
                    AppNotifications.setBadge(applicationContext, body.optInt("unreadCount"))
                    Result.success()
                }
                401 -> { // signed out elsewhere / session over: stop and clear
                    AppNotifications.clearSession(applicationContext)
                    Result.success()
                }
                else -> Result.retry()
            }
        } catch (e: Exception) {
            Log.w("SmartWashNotify", "badge sync failed: ${e.message}")
            Result.retry()
        }
    }
}
