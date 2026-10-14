package com.sanbo.sanbo

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class BackupExportContractTest {
    private fun withSource(test: (File, File) -> Unit) {
        val root = Files.createTempDirectory("sanbo-export-test").toFile()
        try {
            val operation = File(root, "export-1").apply { mkdirs() }
            val source = File(operation, "audit.sanbo").apply { writeText("{}") }
            test(root, source)
        } finally { root.deleteRecursively() }
    }

    private fun rejects(block: () -> Unit) {
        try { block(); fail("source must be rejected") }
        catch (_: IllegalArgumentException) { }
    }

    @Test fun acceptsOnlyAnOwnedRegularFile() = withSource { root, source ->
        assertEquals(source.canonicalFile,
            validatedBackupExportSource(source.path, source.name, root))
        rejects { validatedBackupExportSource(root.path, root.name, root) }
        rejects { validatedBackupExportSource(File(root, "missing.sanbo").path, "missing.sanbo", root) }
        for (name in listOf("", ".", "..", "../audit.sanbo", "a\\b", "a\u0000b", "wrong.sanbo")) {
            rejects { validatedBackupExportSource(source.path, name, root) }
        }
    }

    @Test fun rejectsOutsideAndEscapingSymlink() = withSource { root, _ ->
        val outside = File.createTempFile("sanbo-outside", ".sanbo")
        try {
            outside.writeText("{}")
            rejects { validatedBackupExportSource(outside.path, outside.name, root) }
            val link = File(root, "escape.sanbo")
            Files.createSymbolicLink(link.toPath(), outside.toPath())
            rejects { validatedBackupExportSource(link.path, link.name, root) }
        } finally { outside.delete() }
    }

    @Test fun rejectsEmptyAndOversizedSource() = withSource { root, source ->
        for (length in listOf(0L, 50L * 1024 * 1024 + 1)) {
            RandomAccessFile(source, "rw").use { it.setLength(length) }
            rejects { validatedBackupExportSource(source.path, source.name, root) }
        }
    }

    @Test fun copiesActualBytesAndClosesOutput() = withSource { _, source ->
        var closed = false
        val output = object : ByteArrayOutputStream() {
            override fun close() { closed = true; super.close() }
        }
        copyBackupExport(source) { output }
        assertArrayEquals(byteArrayOf(123, 125), output.toByteArray())
        assertTrue(closed)
    }

    @Test fun propagatesOpenWriteAndCloseFailure() = withSource { _, source ->
        val outputs = listOf<() -> OutputStream>(
            { throw IOException("open failed") },
            { object : OutputStream() {
                override fun write(value: Int) { throw IOException("write failed") }
            } },
            { object : ByteArrayOutputStream() {
                override fun close() { throw IOException("close failed") }
            } },
        )
        for (open in outputs) {
            try { copyBackupExport(source, open); fail("failure must propagate") }
            catch (_: IOException) { }
        }
    }
}
