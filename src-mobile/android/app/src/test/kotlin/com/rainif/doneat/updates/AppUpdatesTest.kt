package com.rainif.doneat.updates

import org.junit.Assert.*
import org.junit.Test

class AppUpdatesTest {
    private fun manifest(code: Long = 6, minSdk: Int = 26) = """{"schemaVersion":1,"applicationId":"com.rainif.doneat.cn","channel":"cn","versionCode":$code,"versionName":"3.2.1","minSdk":$minSdk}"""
    @Test fun newerBuildWithSameDisplayVersionIsAvailable() {
        assertTrue(AppUpdates.evaluate(manifest(), 5, 36) is UpdateResult.Available)
    }
    @Test fun currentAndOlderVersionsNeverOfferDowngrade() {
        assertEquals(UpdateResult.Current, AppUpdates.evaluate(manifest(), 6, 36))
        assertEquals(UpdateResult.Current, AppUpdates.evaluate(manifest(5), 6, 36))
    }
    @Test fun unsupportedAndroidDoesNotOfferInstallation() {
        assertEquals(UpdateResult.Incompatible, AppUpdates.evaluate(manifest(minSdk = 37), 5, 36))
    }
    @Test fun wrongChannelPackageSchemaAndMalformedInputAreRejected() {
        for (body in listOf(manifest().replace("\"cn\"", "\"play\""), manifest().replace("com.rainif.doneat.cn", "com.other.app"), manifest().replace("schemaVersion\":1", "schemaVersion\":2"), manifest(-1), manifest(minSdk = 1), "{}", "<html>error</html>", "x".repeat(17000), manifest().replace("3.2.1", "<script>"))) {
            assertTrue(runCatching { AppUpdates.evaluate(body, 5, 36) }.isFailure)
        }
    }
}
