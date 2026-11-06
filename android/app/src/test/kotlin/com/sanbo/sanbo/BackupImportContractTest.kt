package com.sanbo.sanbo

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class BackupImportContractTest {
    @Test fun abandonedFreshFilesAreRecoveredButActiveAndUnrelatedFilesRemain() {
        val root = Files.createTempDirectory("sanbo-import-contract").toFile()
        try {
            val abandoned = File(root, "import-abandoned.sanbo").apply { writeText("private") }
            val active = File(root, "import-active.sanbo").apply { writeText("active") }
            val unrelated = File(root, "unrelated.txt").apply { writeText("keep") }
            reclaimAbandonedBackupImports(root, setOf(active.path))
            assertFalse(abandoned.exists())
            assertEquals("active", active.readText())
            assertEquals("keep", unrelated.readText())
        } finally { root.deleteRecursively() }
    }
    private fun rejects(block: () -> Unit) {
        try { block(); fail("read must fail") } catch (_: IOException) { }
    }
    @Test fun exactlyAtLimitAndEmptySizeMetadataUseActualBytes() {
        val output = ByteArrayOutputStream()
        copyBoundedBackup(ByteArrayInputStream(byteArrayOf(1, 2, 3, 4)), output, 4) { false }
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), output.toByteArray())
    }
    @Test fun exceedingLimitNeverWritesExtraBytes() {
        val output = ByteArrayOutputStream()
        rejects { copyBoundedBackup(ByteArrayInputStream(ByteArray(5)), output, 4) { false } }
        assertTrue(output.size() <= 4)
    }
    @Test fun interruptedReadDoesNotCopyMoreData() {
        val output = ByteArrayOutputStream()
        rejects { copyBoundedBackup(ByteArrayInputStream(ByteArray(4)), output, 4) { true } }
        assertEquals(0, output.size())
    }
    @Test fun full50MiBStreamDoesNotDependOnReportedSize() {
        val max = 50L * 1024 * 1024
        var remaining = max
        val input = object : InputStream() {
            override fun read(): Int = if (remaining-- > 0) 0 else -1
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                if (remaining == 0L) return -1
                val count = minOf(remaining, length.toLong()).toInt()
                remaining -= count
                return count
            }
        }
        var copied = 0L
        val output = object : java.io.OutputStream() {
            override fun write(value: Int) { copied++ }
            override fun write(bytes: ByteArray, offset: Int, length: Int) { copied += length }
        }
        copyBoundedBackup(input, output, max) { false }
        assertEquals(max, copied)
    }
}
