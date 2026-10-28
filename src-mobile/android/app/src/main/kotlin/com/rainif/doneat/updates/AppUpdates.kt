package com.rainif.doneat.updates

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/** Public channel metadata only: never send installation IDs, receipts or work data. */
@Serializable
data class AndroidRelease(
    val schemaVersion: Int,
    val applicationId: String,
    val channel: String,
    val versionCode: Long,
    val versionName: String,
    val minSdk: Int,
    val releaseNotes: Map<String, String> = emptyMap(),
)

sealed interface UpdateResult {
    data object Current : UpdateResult
    data object Incompatible : UpdateResult
    data class Available(val release: AndroidRelease) : UpdateResult
}

object AppUpdates {
    const val MANIFEST_URL = "https://downloads.doneat.app/android/cn/latest.json"
    const val DOWNLOAD_PAGE = "https://doneat.com.cn/android"
    const val PLAY_PAGE = "https://play.google.com/store/apps/details?id=com.rainif.doneat"
    private const val MAX_BYTES = 16 * 1024
    private val json = Json { ignoreUnknownKeys = true }

    fun evaluate(body: String, installedCode: Long, sdk: Int): UpdateResult {
        require(body.toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
        val release = json.decodeFromString<AndroidRelease>(body)
        require(release.schemaVersion == 1 && release.channel == "cn")
        require(release.applicationId == "com.rainif.doneat.cn")
        require(release.versionCode > 0 && release.minSdk in 26..100)
        require(Regex("[0-9]+(?:\\.[0-9]+){1,3}(?:[-+][A-Za-z0-9.-]+)?").matches(release.versionName))
        require(release.versionName.length <= 40)
        require(release.releaseNotes.size <= 2 && release.releaseNotes.keys.all { it in setOf("en", "zh-CN") })
        require(release.releaseNotes.values.all { it.length <= 3000 && it.none { c -> c.isISOControl() && c != '\n' && c != '\t' } })
        return when {
            release.versionCode <= installedCode -> UpdateResult.Current
            release.minSdk > sdk -> UpdateResult.Incompatible
            else -> UpdateResult.Available(release)
        }
    }

    suspend fun check(installedCode: Long, sdk: Int): UpdateResult = withContext(Dispatchers.IO) {
        val connection = URL(MANIFEST_URL).openConnection() as HttpsURLConnection
        try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "DoneAt-Android-Update/1.0")
            require(connection.responseCode == 200)
            require(connection.contentLengthLong <= MAX_BYTES)
            val bytes = connection.inputStream.use { input ->
                val result = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(2048)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(result.size() + count <= MAX_BYTES)
                    result.write(buffer, 0, count)
                }
                result.toByteArray()
            }
            evaluate(bytes.toString(Charsets.UTF_8), installedCode, sdk)
        } finally { connection.disconnect() }
    }
}
