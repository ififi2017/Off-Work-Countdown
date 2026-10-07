package com.rainif.doneat.plus

/** AtomicFile may log a failed rename without throwing; only exact read-back commits the deadline. */
internal fun confirmedLifetimeOfferWrite(
    bytes: ByteArray,
    write: (ByteArray) -> Unit,
    read: () -> ByteArray,
): Boolean = runCatching {
    write(bytes)
    read().contentEquals(bytes)
}.getOrDefault(false)
