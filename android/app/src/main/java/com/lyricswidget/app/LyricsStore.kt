package com.lyricswidget.app

import android.content.Context
import android.graphics.Bitmap
import android.media.session.MediaController
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.io.File

/**
 * Process-wide state: what is playing, which lyrics are loaded, and the search.
 * Everything here runs on the main thread; searches run on [Net.pool] and post back.
 */
object LyricsStore {
    const val LEAD = 0.15

    private lateinit var dir: File
    private lateinit var searcher: Searcher
    private val main = Handler(Looper.getMainLooper())
    private val listeners = LinkedHashSet<() -> Unit>()

    // ---- what is playing ----
    var hasPlayer = false
    var title = ""
    var artist = ""
    var art: Bitmap? = null
    var playing = false
    var length = 0.0
    var positionKnown = false
    var transport: MediaController.TransportControls? = null
    private var posRef = 0.0
    private var posAt = SystemClock.elapsedRealtime()
    private var speed = 1.0

    // ---- lyrics ----
    var lines: List<Line> = emptyList()
    var idx = -1
    var offset = 0.0
    var status = ""
    var srcLabel = ""
    var cands: List<Cand> = emptyList()
    var curIndex = -1
    var busy = false
    var customQuery = ""
    var pickerOpen = false
    var appVisible = false
    var dismissedKey = ""

    private var lyrArtist = ""
    private var lyrTitle = ""
    private var loadedKey = ""
    private var rawLrc = ""
    private var curPath = ""
    private var gen = 0
    private var localRunning = false
    private var onlineRunning = false
    private var onlineFinished = false
    private var localCands: List<Cand> = emptyList()
    private var onlineCands: List<Cand> = emptyList()
    private var savePending = false
    private val saveRunnable = Runnable { saveCurrent() }

    fun init(ctx: Context) {
        if (::dir.isInitialized) return
        dir = File(ctx.applicationContext.filesDir, "lyrics").apply { mkdirs() }
        searcher = Searcher(dir)
    }

    fun addListener(l: () -> Unit) { listeners.add(l) }
    fun removeListener(l: () -> Unit) { listeners.remove(l) }
    private fun changed() { for (l in listeners.toList()) l() }

    fun key(): String = "$artist|$title"
    fun dismiss() { dismissedKey = key(); changed() }
    fun undismiss() { dismissedKey = ""; changed() }

    // ---- timing ----
    fun curPos(): Double {
        val p = posRef + if (playing && positionKnown) (SystemClock.elapsedRealtime() - posAt) / 1000.0 * speed else 0.0
        return if (length > 0.0) minOf(p, length) else p
    }

    /** Updates [idx] from the playback position. Returns true if the current line changed. */
    fun tick(): Boolean {
        if (lines.isEmpty() || !positionKnown) return false
        val p = curPos() + LEAD + offset + 1e-8
        var lo = 0
        var hi = lines.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (lines[mid].t <= p) lo = mid + 1 else hi = mid
        }
        val n = lo - 1
        if (n != idx) { idx = n; return true }
        return false
    }

    // ---- media updates (from MediaTracker) ----
    fun noPlayer() {
        if (!hasPlayer && art == null) return
        hasPlayer = false
        playing = false
        art = null
        changed()
    }

    fun onMedia(
        has: Boolean, t: String, a: String, bmp: Bitmap?, len: Double,
        pos: Double, known: Boolean, isPlaying: Boolean, spd: Double
    ) {
        val trackChanged = has && (t != title || a != artist)
        hasPlayer = has
        art = if (has) bmp else null
        positionKnown = known
        if (known) posRef = pos else if (trackChanged) posRef = 0.0 else if (playing) posRef = curPos()
        posAt = SystemClock.elapsedRealtime()
        if (trackChanged || len > 0.0) length = len
        speed = spd
        playing = isPlaying
        if (trackChanged) {
            title = t
            artist = a
            fetchLyrics(false, "")
        } else {
            tick()
            changed()
        }
    }

    // ---- searching ----
    fun fetchLyrics(force: Boolean, query: String) {
        if (title.isEmpty()) return
        val k = key()
        if (!force && k == loadedKey) return
        flushSave()
        customQuery = query
        lyrArtist = artist
        lyrTitle = title
        loadedKey = k
        gen++
        val g = gen
        lines = emptyList()
        idx = -1
        localCands = emptyList()
        onlineCands = emptyList()
        cands = emptyList()
        curIndex = -1
        rawLrc = ""
        curPath = ""
        srcLabel = ""
        offset = 0.0
        localRunning = true
        onlineFinished = false
        onlineRunning = false
        busy = true
        status = "checking saved lyrics…"
        val t = lyrTitle
        val a = lyrArtist
        Net.pool.execute {
            val res = try { searcher.local(t, a, query) } catch (e: Exception) { emptyList() }
            main.post { onLocal(g, res) }
        }
        main.postDelayed({ watchdog(g) }, 30000)
        changed()
    }

    private fun watchdog(g: Int) {
        if (g != gen || !busy) return
        gen++
        localRunning = false
        onlineRunning = false
        busy = false
        if (lines.isEmpty()) status = "search timed out, tap ↻ to retry"
        changed()
    }

    fun runOnline() {
        if (localRunning || onlineRunning || onlineFinished || lyrTitle.isEmpty()) return
        onlineRunning = true
        busy = true
        if (lines.isEmpty()) status = "searching online…"
        val g = gen
        val t = lyrTitle
        val a = lyrArtist
        val len = length
        val q = customQuery
        Net.pool.execute {
            val res = try {
                searcher.online(t, a, len, q)
            } catch (e: Exception) {
                OnlineResult(emptyList(), 0, true)
            }
            main.post { onOnline(g, res) }
        }
        changed()
    }

    private fun rebuild() { cands = localCands + onlineCands }

    private fun onLocal(g: Int, res: List<Cand>) {
        if (g != gen) return
        localRunning = false
        localCands = res
        rebuild()
        if (localCands.isNotEmpty() && customQuery.isEmpty()) {
            applyCandidate(0, false)
            busy = onlineRunning
            if (pickerOpen) runOnline()
            changed()
            return
        }
        runOnline()
    }

    private fun onOnline(g: Int, res: OnlineResult) {
        if (g != gen) return
        onlineRunning = false
        onlineCands = res.cands
        rebuild()
        onlineFinished = true
        busy = false
        if (lines.isEmpty()) {
            if (cands.isEmpty()) {
                status = when {
                    res.failed -> "search failed, tap ↻ to retry"
                    res.netErrors > 0 -> "couldn't reach the lyric sources, tap ↻ to retry"
                    else -> "no lyrics found, tap ↻ to retry"
                }
            } else if (customQuery.isEmpty() && cands[0].score >= 0.55) {
                applyCandidate(0, false)
            } else {
                status = "${cands.size} possible matches, tap ☰ to choose"
            }
        }
        changed()
    }

    fun applyCandidate(i: Int, save: Boolean): Boolean {
        val cd = cands.getOrNull(i) ?: return false
        val (parsed, offMs) = Lrc.parse(cd.lrc)
        if (parsed.isEmpty()) {
            status = "that file has no timestamps"
            changed()
            return false
        }
        flushSave()
        curIndex = i
        lines = parsed
        rawLrc = cd.lrc
        curPath = cd.path
        offset = offMs / 1000.0
        srcLabel = if (cd.source == "local") "local" else "${cd.source} · ${Math.round(cd.score * 100)}%"
        status = ""
        idx = -1
        tick()
        if (save) saveCurrent()
        changed()
        return true
    }

    // ---- saving ----
    private fun scheduleSave() {
        savePending = true
        main.removeCallbacks(saveRunnable)
        main.postDelayed(saveRunnable, 700)
    }

    private fun flushSave() {
        if (savePending) {
            main.removeCallbacks(saveRunnable)
            saveCurrent()
        }
    }

    private fun saveCurrent() {
        savePending = false
        if (rawLrc.isEmpty() || lyrTitle.isEmpty()) return
        val text = Lrc.withOffset(rawLrc, Math.round(offset * 1000).toInt())
        val keep = curPath.isNotEmpty() && File(curPath).parentFile?.canonicalPath == dir.canonicalPath
        val dest = if (keep) File(curPath) else File(dir, Lrc.safeName(lyrArtist, lyrTitle) + ".lrc")
        curPath = dest.absolutePath
        Net.pool.execute {
            try {
                dest.parentFile?.mkdirs()
                dest.writeText(text)
            } catch (e: Exception) {
                // Saving is best effort; lyrics keep working from memory.
            }
        }
    }

    // ---- actions from the UI ----
    fun reload() { if (hasPlayer) fetchLyrics(true, "") }
    fun autoSearch() = reload()

    fun search(q: String) {
        val t = q.trim()
        if (t.isEmpty()) {
            if (customQuery.isNotEmpty()) autoSearch()
            return
        }
        if (hasPlayer && title.isNotEmpty()) fetchLyrics(true, t)
    }

    fun pick(i: Int): Boolean = applyCandidate(i, true)

    fun notifyPicker(open: Boolean) {
        pickerOpen = open
        if (open) runOnline()
    }

    fun syncTo(i: Int) {
        if (!positionKnown || i !in lines.indices) return
        offset = lines[i].t - (curPos() + LEAD)
        idx = i
        scheduleSave()
        changed()
    }

    fun nudge(delta: Double) {
        if (lines.isEmpty()) return
        offset = Math.round((offset + delta) * 1000) / 1000.0
        scheduleSave()
        tick()
        changed()
    }

    fun importLrc(text: String): Boolean {
        if (!Lrc.synced(text) || lyrTitle.isEmpty()) return false
        val c = Cand("local", lyrArtist, lyrTitle, "", 0.0, 2.0, text, "")
        localCands = listOf(c) + localCands
        rebuild()
        return applyCandidate(0, true)
    }

    // ---- playback controls ----
    fun prev() { transport?.skipToPrevious() }
    fun next() { transport?.skipToNext() }
    fun toggle() { if (playing) transport?.pause() else transport?.play() }
    fun seekTo(sec: Double) { transport?.seekTo((sec * 1000).toLong()) }
}
