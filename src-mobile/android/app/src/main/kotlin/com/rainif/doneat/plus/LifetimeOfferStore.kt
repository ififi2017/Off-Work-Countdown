package com.rainif.doneat.plus

import android.content.Context
import android.util.AtomicFile
import java.io.File
import org.json.JSONObject

/** This invitation never enters schema 7, Auto Backup or device transfer. */
internal class LifetimeOfferStore(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "lifetime-offer-321.json"))
    var isUsable = true
        private set

    fun load(): LifetimeOffer? {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists() &&
            !File(file.baseFile.path + ".new").exists()) return null
        return try {
            val data = JSONObject(file.openRead().bufferedReader().use { it.readText() })
            val latest = data.getLong("latestObservedAtMs")
            val claimed = if (data.isNull("claimedAtMs")) null else data.getLong("claimedAtMs")
            require(latest >= 0 && (claimed == null || claimed in 0..latest))
            require(claimed == null || claimed <= Long.MAX_VALUE - LifetimeOffer.DURATION_MS)
            LifetimeOffer(LifetimeOfferSource.valueOf(data.getString("source")), latest, claimed)
        } catch (_: Exception) {
            // Damaged state must not grant another 24 hours by treating it as a new invitation.
            isUsable = false
            null
        }
    }

    fun save(offer: LifetimeOffer): Boolean {
        if (!isUsable) return false
        return try {
            val data = JSONObject().put("source", offer.source.name)
                .put("latestObservedAtMs", offer.latestObservedAtMs)
                .put("claimedAtMs", offer.claimedAtMs ?: JSONObject.NULL).toString().toByteArray()
            require(confirmedLifetimeOfferWrite(data, write = { bytes ->
                val stream = file.startWrite()
                try {
                    stream.write(bytes)
                    stream.fd.sync()
                    file.finishWrite(stream)
                } catch (error: Exception) { file.failWrite(stream); throw error }
            }, read = { file.openRead().use { it.readBytes() } }))
            true
        } catch (_: Exception) {
            isUsable = false
            false
        }
    }
}
