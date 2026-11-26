package com.lyricswidget.app

import android.content.Context
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/** Restores one recent automatic match without putting it in the user's saved lyrics or backups. */
internal class RecentLyricsCache(ctx: Context) {
    private val file = AtomicFile(File(ctx.noBackupFilesDir, "recent-auto-lyrics.json"))
    private val writer = Executors.newSingleThreadExecutor()

    @Synchronized
    fun get(title: String, artist: String): Cand? = try {
        val json = JSONObject(file.readFully().toString(Charsets.UTF_8))
        val age = System.currentTimeMillis() - json.getLong("time")
        if (json.optString("title") != title || json.optString("artist") != artist ||
            age !in 0L..(7 * 24 * 60 * 60 * 1000L)) {
            null
        } else {
            Cand(json.getString("source"), artist, title, "", 0.0,
                json.getDouble("score"), json.getString("lrc"), "")
        }
    } catch (_: Exception) {
        null
    }

    fun put(title: String, artist: String, result: Cand) {
        writer.execute { write(title, artist, result) }
    }

    @Synchronized
    private fun write(title: String, artist: String, result: Cand) {
        val data = JSONObject().put("title", title).put("artist", artist)
            .put("source", result.source).put("score", result.score)
            .put("lrc", result.lrc).put("time", System.currentTimeMillis())
            .toString().toByteArray(Charsets.UTF_8)
        if (data.size > 128 * 1024) {
            file.delete()
            return
        }
        val out = try { file.startWrite() } catch (_: Exception) { return }
        try {
            out.write(data)
            file.finishWrite(out)
        } catch (_: Exception) {
            file.failWrite(out)
        }
    }
}
