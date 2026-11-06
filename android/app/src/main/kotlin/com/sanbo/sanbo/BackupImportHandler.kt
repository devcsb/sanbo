package com.sanbo.sanbo

import android.app.Activity
import android.content.Intent
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ConcurrentHashMap

internal const val maxBackupImportBytes = 50L * 1024 * 1024
private val activeBackupImportPaths = ConcurrentHashMap.newKeySet<String>()

internal fun reclaimAbandonedBackupImports(root: File, activePaths: Set<String>) {
    root.listFiles()?.filter { it.isFile && it.name.startsWith("import-") && it.path !in activePaths }?.forEach { it.delete() }
}

internal fun copyBoundedBackup(input: InputStream, output: OutputStream, limit: Long, stopped: () -> Boolean) {
    val buffer = ByteArray(8192)
    var copied = 0L
    while (true) {
        if (stopped()) throw IOException("cancelled")
        val count = input.read(buffer)
        if (stopped()) throw IOException("cancelled")
        if (count < 0) return
        if (count > limit - copied) throw IOException("too_large")
        output.write(buffer, 0, count)
        copied += count
    }
}

/** Owns one picker/read/cache lease. Provider metadata never controls allocation. */
internal class BackupImportHandler(private val activity: FlutterFragmentActivity) {
    private class Pending(val code: Int, val result: MethodChannel.Result, val source: File, val id: String) {
        val signal = CancellationSignal()
        @Volatile var stopped = false
        var reading = false
        var answered = false
        var descriptor: ParcelFileDescriptor? = null
        fun stop() {
            stopped = true
            signal.cancel()
            val open = synchronized(this) { descriptor.also { descriptor = null } }
            try { open?.close() } catch (_: IOException) { }
        }
    }
    private val root = File(activity.cacheDir, "sanbo_imports")
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private var channel: MethodChannel? = null
    private var pending: Pending? = null
    private var closed = false

    fun attach(messenger: BinaryMessenger) {
        root.mkdirs()
        // Process restart empties the active set; Activity recreation preserves it.
        reclaimAbandonedBackupImports(root, activeBackupImportPaths)
        channel = MethodChannel(messenger, "sanbo/backup_import").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> pick((call.arguments as? Map<*, *>)?.get("operationId") as? String, result)
                    "cancel" -> {
                        val id = (call.arguments as? Map<*, *>)?.get("operationId")
                        pending?.takeIf { it.id == id }?.let { cancel(it, "import_cancelled") }
                        result.success(null)
                    }
                    "release" -> {
                        val id = (call.arguments as? Map<*, *>)?.get("operationId")
                        pending?.takeIf { it.id == id && !it.reading }?.let { clear(it) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun pick(operationId: String?, result: MethodChannel.Result) {
        if (operationId.isNullOrEmpty() || operationId.length > 128) {
            result.error("invalid_arguments", "Invalid import identifier.", null); return
        }
        // A recreated Activity must also wait for the previous provider to close.
        if (closed || pending != null || activeBackupImportPaths.isNotEmpty()) {
            result.error("import_busy", "Another file operation is active.", null)
            return
        }
        val operation = try {
            Pending(allocateBackupRequestCode(), result, File.createTempFile("import-", ".sanbo", root), operationId)
        } catch (_: Exception) {
            result.error("import_failed", "Unable to prepare import.", null); return
        }
        pending = operation
        activeBackupImportPaths.add(operation.source.path)
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "application/octet-stream"))
            }, operation.code)
        } catch (_: Exception) { fail(operation, "import_unavailable"); clear(operation) }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val operation = pending ?: return false
        if (requestCode != operation.code) return false
        if (operation.reading || operation.answered) return true
        val uri = data?.data
        if (resultCode == Activity.RESULT_CANCELED) {
            operation.answered = true; operation.result.success(null); clear(operation); return true
        }
        if (resultCode != Activity.RESULT_OK || uri == null) {
            fail(operation, "import_failed"); clear(operation); return true
        }
        operation.reading = true
        val deadline = timer.schedule({
            operation.stopped = true
            activity.runOnUiThread { fail(operation, "import_timeout") }
            operation.stop()
        }, 30, TimeUnit.SECONDS)
        worker.execute {
            var name = "backup.sanbo"
            var failure: String? = null
            try {
                val resolver = activity.contentResolver
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null, operation.signal)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex) && cursor.getLong(sizeIndex) > maxBackupImportBytes) throw IOException("too_large")
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex).take(255)
                    }
                }
                val descriptor = resolver.openFileDescriptor(uri, "r", operation.signal) ?: throw IOException("unavailable")
                synchronized(operation) {
                    if (operation.stopped) { descriptor.close(); throw IOException("cancelled") }
                    operation.descriptor = descriptor
                }
                ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                    operation.source.outputStream().buffered().use { output ->
                        copyBoundedBackup(input, output, maxBackupImportBytes) { operation.stopped }
                    }
                }
            } catch (error: Exception) {
                failure = if (error.message == "too_large") "import_too_large" else "import_failed"
            } finally {
                deadline.cancel(false)
                synchronized(operation) { operation.descriptor = null }
                if (operation.stopped || failure != null) operation.source.delete()
            }
            activity.runOnUiThread {
                operation.reading = false
                if (pending !== operation) { operation.source.delete(); return@runOnUiThread }
                if (operation.stopped || failure != null || closed) {
                    fail(operation, failure ?: "import_interrupted"); clear(operation)
                } else {
                    operation.answered = true
                    operation.result.success(mapOf("operationId" to operation.id, "sourcePath" to operation.source.path, "fileName" to name))
                    // Keep the lease until Dart has finished its bounded read.
                }
            }
        }
        return true
    }

    private fun fail(operation: Pending, code: String) {
        if (operation.answered) return
        operation.answered = true
        operation.result.error(code, "File import did not complete.", null)
    }

    private fun clear(operation: Pending) {
        activeBackupImportPaths.remove(operation.source.path)
        operation.source.delete()
        if (pending === operation) pending = null
    }

    private fun cancel(operation: Pending, code: String) {
        operation.stopped = true
        fail(operation, code)
        timer.execute { operation.stop() }
        if (!operation.reading) {
            try { activity.finishActivity(operation.code) } catch (_: Exception) { }
            clear(operation)
        }
        // A blocked provider must finish closing before another read starts.
    }

    fun close() {
        if (closed) return
        closed = true
        channel?.setMethodCallHandler(null)
        channel = null
        pending?.let { cancel(it, "import_interrupted") }
        worker.shutdown()
        timer.shutdown()
    }
}
