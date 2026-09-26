package com.rainif.doneat.core.data

/** Cheap byte-level guard before handing a user file to the recursive JSON parser. */
internal object RecordInputBounds {
    private const val MAX_DEPTH = 128
    private const val MAX_CONTAINERS = 200_000
    // The byte ceiling remains the main size limit. This catches tiny repeated
    // values that otherwise create a very large parser tree below that ceiling.
    private const val MAX_ENTRIES_PER_CONTAINER = 100_000

    fun accepts(bytes: ByteArray): Boolean {
        if (bytes.size > FirstRunRestore.MAX_BYTES) return false
        val entries = IntArray(MAX_DEPTH)
        var depth = 0
        var containers = 0
        var quoted = false
        var escaped = false
        for (byte in bytes) {
            val c = byte.toInt().toChar()
            if (quoted) {
                when {
                    escaped -> escaped = false
                    c == '\\' -> escaped = true
                    c == '"' -> quoted = false
                }
                continue
            }
            when (c) {
                '"' -> quoted = true
                '{', '[' -> {
                    if (++containers > MAX_CONTAINERS || depth == MAX_DEPTH) return false
                    entries[depth++] = 0
                }
                '}', ']' -> if (depth-- == 0) return false
                ',' -> if (depth > 0 && ++entries[depth - 1] >= MAX_ENTRIES_PER_CONTAINER) return false
            }
        }
        return !quoted && depth == 0
    }
}
