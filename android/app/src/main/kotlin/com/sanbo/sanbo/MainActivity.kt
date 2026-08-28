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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

internal const val notificationKindExtra = "sanbo_notification_kind"
internal const val notificationSessionIdExtra = "sanbo_notification_session_id"

internal fun notificationKind(kind: String?): String? = kind?.takeIf { it == "highSpeed" }

internal fun notificationKind(intent: Intent?): String? =
    notificationKind(intent?.getStringExtra(notificationKindExtra))

internal fun notificationSessionId(sessionId: String?): String? =
    sessionId?.takeIf { it.isNotEmpty() }

internal fun notificationSessionId(intent: Intent?): String? =
    notificationSessionId(intent?.getStringExtra(notificationSessionIdExtra))

internal fun shouldDeliverNotificationTap(
    channelReady: Boolean,
    hasChannel: Boolean,
): Boolean = channelReady && hasChannel

internal fun shouldAcceptNotificationReadinessAck(
    currentGeneration: Int,
    ackGeneration: Int,
): Boolean = currentGeneration == ackGeneration

class MainActivity : FlutterFragmentActivity() {
    private val methodChannelName = "sanbo/session_notifications"
    private val notificationChannelId = "sanbo_session_alerts"
    private var notificationMethodChannel: MethodChannel? = null
    private var notificationChannelReady = false
    private var notificationChannelGeneration = 0
    private var pendingKind: String? = null
    private var pendingSessionId: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        // A configuration change can create a new Dart messenger. Never reuse
        // the previous engine's readiness acknowledgement for this channel.
        notificationChannelReady = false
        val channelGeneration = ++notificationChannelGeneration
        notificationMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        if (shouldAcceptNotificationReadinessAck(
                                currentGeneration = notificationChannelGeneration,
                                ackGeneration = channelGeneration,
                            )
                        ) {
                            notificationChannelReady = true
                            flushPendingTap()
                        }
                        result.success(null)
                    }
                    "getTimezone" -> result.success(java.util.TimeZone.getDefault().id)
                    "requestPermission" -> requestNotificationPermission(result)
                    "show" -> {
                        val id = call.argument<Int>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val kind = call.argument<String>("kind")
                        val sessionId = call.argument<String>("sessionId")
                        if (id == null ||
                            !isSupportedNotification(id, kind, sessionId) ||
                            title == null ||
                            body == null
                        ) {
                            result.error("invalid_arguments", "Notification fields are missing or invalid.", null)
                            return@setMethodCallHandler
                        }
                        showNotification(id, title, body, kind, sessionId)
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
        val sessionId = notificationSessionId(intent) ?: return
        val channel = notificationMethodChannel
        if (!shouldDeliverNotificationTap(
                channelReady = notificationChannelReady,
                hasChannel = channel != null,
            )
        ) {
            pendingKind = kind
            pendingSessionId = sessionId
        } else {
            channel?.invokeMethod(
                "notificationTapped",
                mapOf("kind" to kind, "sessionId" to sessionId),
            )
        }
        intent?.removeExtra(notificationKindExtra)
        intent?.removeExtra(notificationSessionIdExtra)
    }

    private fun flushPendingTap() {
        val kind = pendingKind ?: return
        val sessionId = pendingSessionId
        pendingKind = null
        pendingSessionId = null
        notificationMethodChannel?.invokeMethod(
            "notificationTapped",
            mapOf("kind" to kind, "sessionId" to sessionId),
        )
    }

    private fun isSupportedNotification(
        id: Int?,
        kind: String?,
        sessionId: String?,
    ): Boolean = when (id) {
        stationaryWarningId -> kind == "stationary" || kind == "duration"
        highSpeedWarningId -> kind == "highSpeed" && !sessionId.isNullOrEmpty()
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

    private fun showNotification(
        id: Int,
        title: String,
        body: String,
        kind: String?,
        sessionId: String?,
    ) {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (kind != null) putExtra(notificationKindExtra, kind)
            if (!sessionId.isNullOrEmpty()) {
                putExtra(notificationSessionIdExtra, sessionId)
            }
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
