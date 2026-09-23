package com.rainif.doneat.ui.files

import android.content.Context
import android.net.Uri

/**
 * Backup files through the system document picker: no storage permission,
 * only the file the user chose.
 */
object BackupFiles {
    /**
     * Reads at most [limit] + 1 bytes, so an oversized file is recognised
     * without being read whole. Null when the file cannot be opened.
     */
    fun read(context: Context, uri: Uri, limit: Long): ByteArray? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { input ->
            val cap = limit + 1
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (out.size() < cap) {
                val read = input.read(buffer, 0, minOf(buffer.size.toLong(), cap - out.size()).toInt())
                if (read < 0) break
                out.write(buffer, 0, read)
            }
            out.toByteArray()
        }
    }.getOrNull()

    /** Writes [text] to the document the user created; false when it could not be written. */
    fun write(context: Context, uri: Uri, text: String): Boolean = runCatching {
        context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) } != null
    }.getOrDefault(false)

    /** Picker types: a backup is JSON, but file providers label it inconsistently. */
    val OPEN_TYPES = arrayOf("application/json", "application/octet-stream", "text/plain")
}
