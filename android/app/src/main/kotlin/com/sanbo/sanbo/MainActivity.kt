package com.sanbo.sanbo

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

internal const val notificationKindExtra = "sanbo_notification_kind"

internal fun notificationKind(kind: String?): String? = kind?.takeIf { it == "highSpeed" }

internal fun notificationKind(intent: Intent?): String? =
    notificationKind(intent?.getStringExtra(notificationKindExtra))

class MainActivity : FlutterActivity() {
    private val methodChannelName = "sanbo/session_notifications"
    private val notificationChannelId = "sanbo_session_alerts"
    private var notificationMethodChannel: MethodChannel? = null
    private var pendingKind: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        notificationMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "show" -> {
                        val id = call.argument<Int>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val kind = call.argument<String>("kind")
                        if (id == null ||
                            !isSupportedNotification(id, kind) ||
                            title == null ||
                            body == null
                        ) {
                            result.error("invalid_arguments", "Notification fields are missing or invalid.", null)
                            return@setMethodCallHandler
                        }
                        showNotification(id, title, body, kind)
                        result.success(null)
                    }

                    "cancel" -> {
                        call.argument<Int>("id")?.let { id ->
                            try {
                                notificationManager().cancel(id)
                            } catch (_: SecurityException) {
                                // A revoked notification permission must not stop tracking.
                            }
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        }
        pendingKind?.let { kind ->
            pendingKind = null
            notificationMethodChannel?.invokeMethod("notificationTapped", mapOf("kind" to kind))
        }
        deliverOrQueueTap(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverOrQueueTap(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun deliverOrQueueTap(intent: Intent?) {
        val kind = notificationKind(intent) ?: return
        val channel = notificationMethodChannel
        if (channel == null) {
            pendingKind = kind
        } else {
            channel.invokeMethod("notificationTapped", mapOf("kind" to kind))
        }
        intent?.removeExtra(notificationKindExtra)
    }

    private fun isSupportedNotification(id: Int?, kind: String?): Boolean = when (id) {
        stationaryWarningId -> kind == "stationary" || kind == "duration"
        highSpeedWarningId -> kind == "highSpeed"
        completionNotificationId -> kind == null
        else -> false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            notificationChannelId,
            "산책 기록 알림",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "장시간 정지와 자동 종료를 알려드려요"
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun showNotification(id: Int, title: String, body: String, kind: String?) {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (kind != null) putExtra(notificationKindExtra, kind)
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            id,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_walk)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        try {
            notificationManager().notify(id, notification)
        } catch (_: SecurityException) {
            // Android 13+ users can revoke notifications at any time.
        }
    }

    private fun notificationManager(): NotificationManager {
        return getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    private companion object {
        const val stationaryWarningId = 4101
        const val completionNotificationId = 4102
        const val highSpeedWarningId = 4103
        const val notificationPermissionRequestCode = 4104
    }
}
