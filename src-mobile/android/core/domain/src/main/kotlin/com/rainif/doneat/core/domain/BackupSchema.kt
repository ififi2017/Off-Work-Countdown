package com.rainif.doneat.core.domain

/** User backup wire versions (RecordJSON); independent of Room and fixture versions. */
object BackupSchema {
    const val EXPORT_VERSION = 6
    val ACCEPTED_VERSIONS = 1..6

    fun accepts(version: Int): Boolean = version in ACCEPTED_VERSIONS
}
