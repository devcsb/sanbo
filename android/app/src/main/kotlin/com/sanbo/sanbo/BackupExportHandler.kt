package com.sanbo.sanbo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal fun validatedBackupExportSource(sourcePath: String, fileName: String, exportRoot: File): File {
    require(fileName.isNotBlank() && fileName != "." && fileName != "..")
    require(!fileName.contains('/') && !fileName.contains('\\') && !fileName.contains('\u0000'))
    val root = exportRoot.canonicalFile
    val source = File(sourcePath).canonicalFile
    require(source.path.startsWith(root.path + File.separator))
    require(source.name == fileName && source.isFile)
    require(source.length() in 1..(50L * 1024 * 1024))
    return source
}

internal fun copyBackupExport(source: File, openOutput: () -> OutputStream) {
    openOutput().use { output -> source.inputStream().use { input -> input.copyTo(output) } }
}

// Late Activity results must not complete a newer picker (16-bit request limit).
private var nextBackupRequestCode = 4105

internal class BackupExportHandler(private val activity: FlutterFragmentActivity) {
    private class Pending(val source: File, val result: MethodChannel.Result, val requestCode: Int) {
        var copying = false
        var interrupted = false
    }
    private val executor = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var pending: Pending? = null
    private var closed = false

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "sanbo/backup_export").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "save") { result.notImplemented(); return@setMethodCallHandler }
                if (closed) {
                    result.error("export_unavailable", "File export is unavailable.", null)
                    return@setMethodCallHandler
                }
                if (pending != null) {
                    result.error("export_busy", "Another file export is active.", null)
                    return@setMethodCallHandler
                }
                val args = call.arguments as? Map<*, *>
                val path = args?.get("sourcePath") as? String
                val name = args?.get("fileName") as? String
                val source = try {
                    require(path != null && name != null)
                    validatedBackupExportSource(path, name, File(activity.cacheDir, "sanbo_exports"))
                } catch (_: Exception) {
                    result.error("invalid_arguments", "The export file is invalid.", null)
                    return@setMethodCallHandler
                }
                val code = nextBackupRequestCode
                nextBackupRequestCode = if (code >= 65530) 4105 else code + 1
                val operation = Pending(source, result, code)
                pending = operation
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    activity.startActivityForResult(intent, code)
                } catch (_: ActivityNotFoundException) {
                    fail(operation, "export_unavailable")
                } catch (_: Exception) {
                    fail(operation, "export_failed")
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val operation = pending ?: return false
        if (operation.requestCode != requestCode) return false
        if (operation.copying) return true
        if (resultCode == Activity.RESULT_CANCELED) {
            finish(operation) { it.success(null) }
            return true
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            fail(operation, "export_failed")
            return true
        }
        operation.copying = true
        executor.execute {
            val copied = try {
                copyBackupExport(operation.source) {
                    activity.contentResolver.openOutputStream(uri, "w")
                        ?: throw IOException("output unavailable")
                }
                true
            } catch (_: Exception) { false }
            activity.runOnUiThread {
                when {
                    operation.interrupted -> fail(operation, "export_interrupted")
                    !copied -> fail(operation, "export_failed")
                    else -> finish(operation) { it.success(uri.toString()) }
                }
            }
        }
        return true
    }

    private fun fail(operation: Pending, code: String) =
        finish(operation) { it.error(code, "File export did not complete.", null) }

    private fun finish(operation: Pending, respond: (MethodChannel.Result) -> Unit) {
        if (pending !== operation) return
        pending = null
        respond(operation.result)
    }

    fun close() {
        if (closed) return
        closed = true
        channel?.setMethodCallHandler(null)
        channel = null
        pending?.let { operation ->
            if (operation.copying) {
                // Dart must retain the source until the stream closes.
                operation.interrupted = true
            } else {
                try { activity.finishActivity(operation.requestCode) } catch (_: Exception) { }
                fail(operation, "export_interrupted")
            }
        }
        executor.shutdown()
    }
}
