package com.lyricswidget.app

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.Normalizer
import java.util.concurrent.Callable
import java.util.concurrent.atomic.AtomicInteger

class Cand(
    val source: String,
    val artist: String,
    val title: String,
    val album: String,
    val duration: Double,
    val score: Double,
    val lrc: String,
    val path: String
)

class Meta(
    val source: String,
    val artist: String,
    val title: String,
    val album: String,
    val duration: Double,
    val fetch: () -> String?
) {
    var score = 0.0
}

class OnlineResult(val cands: List<Cand>, val netErrors: Int, val failed: Boolean)

/** Title/artist matching, ported from the desktop versions' lyrsearch. */
object Match {
    private val SPACES = Regex("""\s+""")
    private val BRACKETS = Regex("""\([^)]*\)|\[[^\]]*]|（[^）]*）|【[^】]*】|《[^》]*》""")
    private val SUFFIX1 = Regex("""\s+-\s+(remaster(ed)?|live|official|lyrics?|video|audio|single|\d{4})\b.*$""", RegexOption.IGNORE_CASE)
    private val SUFFIX2 = Regex("""\s+(official|lyric video|lyrics|music video|audio|mv)\b.*$""", RegexOption.IGNORE_CASE)
    private val SUFFIX3 = Regex("""\s+(feat|ft)\.?\s.*$""", RegexOption.IGNORE_CASE)
    private val TOPIC = Regex("""\s*-\s*topic$""", RegexOption.IGNORE_CASE)
    private val VEVO = Regex("""vevo$""", RegexOption.IGNORE_CASE)
    private val ARTIST_SPLIT = Regex("""\s*(?:,|;|&|\band\b|\bx\b|\bfeat\.?|\bft\.?)\s*""", RegexOption.IGNORE_CASE)
    private val DASH_SPLIT = Regex("""^(.+?)\s+[-–—|]\s+(.+)$""")
    private val WORD = Regex("""[\p{L}\p{N}_]+""")

    fun norm(s: String?): String {
        val n = Normalizer.normalize(s ?: "", Normalizer.Form.NFKC).lowercase()
        return buildString { for (ch in n) if (ch.isLetterOrDigit()) append(ch) }
    }

    private fun matching(a: String, b: String): Int {
        if (a.isEmpty() || b.isEmpty()) return 0
        var best = 0
        var endA = 0
        var endB = 0
        var prev = IntArray(b.length + 1)
        var cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            for (j in 1..b.length) {
                if (a[i - 1] == b[j - 1]) {
                    cur[j] = prev[j - 1] + 1
                    if (cur[j] > best) {
                        best = cur[j]
                        endA = i
                        endB = j
                    }
                } else {
                    cur[j] = 0
                }
            }
            val t = prev
            prev = cur
            cur = t
        }
        if (best == 0) return 0
        val sa = endA - best
        val sb = endB - best
        return best + matching(a.substring(0, sa), b.substring(0, sb)) +
            matching(a.substring(endA), b.substring(endB))
    }

    /** Same idea as Python's SequenceMatcher.ratio(). */
    fun ratio(a: String, b: String): Double {
        val total = a.length + b.length
        return if (total == 0) 1.0 else 2.0 * matching(a, b) / total
    }

    fun sim(a0: String, b0: String): Double {
        val a = norm(a0)
        val b = norm(b0)
        if (a.isEmpty() || b.isEmpty()) return 0.0
        if (a == b) return 1.0
        val shortS = if (a.length <= b.length) a else b
        val longS = if (a.length <= b.length) b else a
        val r = ratio(a, b)
        if (shortS.length >= 3 && longS.contains(shortS) && shortS.length.toDouble() / longS.length >= 0.5) {
            return maxOf(0.88, r)
        }
        return r
    }

    fun cleanTitle(s0: String): String {
        var s = BRACKETS.replace(s0, " ")
        s = SUFFIX1.replace(s, "")
        s = SUFFIX2.replace(s, "")
        s = SUFFIX3.replace(s, "")
        s = SPACES.replace(s, " ")
        return s.trim { it == ' ' || it == '-' || it == '–' || it == '—' || it == '|' }
    }

    fun artistOptions(a0: String): List<String> {
        var a = TOPIC.replace(a0.trim(), "")
        a = VEVO.replace(a, "").trim()
        val opts = ArrayList<String>()
        if (a.isNotEmpty()) opts.add(a)
        for (p0 in ARTIST_SPLIT.split(a)) {
            val p = p0.trim()
            if (p.isNotEmpty() && p !in opts) opts.add(p)
        }
        return opts.take(3)
    }

    fun buildPairs(title: String, artist: String): List<Pair<String, String>> {
        val pairs = ArrayList<Pair<String, String>>()
        fun add(ar0: String, ti0: String) {
            val ar = ar0.trim()
            val ti = ti0.trim()
            val p = Pair(ar, ti)
            if (ti.isNotEmpty() && p !in pairs) pairs.add(p)
        }
        val arts = artistOptions(artist)
        val m = DASH_SPLIT.find(title.trim())
        if (m != null) {
            val left = cleanTitle(m.groupValues[1])
            val right = cleanTitle(m.groupValues[2])
            add(left, right)
            add(right, left)
            if (arts.isNotEmpty()) {
                add(arts[0], left)
                add(arts[0], right)
            }
            add("", left)
            add("", right)
        } else {
            val t = cleanTitle(title)
            for (a in arts.take(2)) add(a, t)
            add("", t)
        }
        return pairs.take(8)
    }

    fun buildKeywords(pairs: List<Pair<String, String>>): List<String> {
        val kws = ArrayList<String>()
        for ((ar, ti) in pairs) {
            val k = "$ar $ti".trim()
            if (k.isNotEmpty() && k !in kws) kws.add(k)
        }
        return kws.take(6)
    }

    fun localScore(stem: String, pairs: List<Pair<String, String>>, rawTitle: String): Double {
        val n = norm(stem)
        val nt = norm(rawTitle)
        var best = 0.0
        if (nt.length >= 4 && (n.contains(nt) || (n.length >= 6 && nt.contains(n)))) best = 0.97
        for ((ar, ti) in pairs) {
            val t = norm(ti)
            val a = norm(ar)
            if (t.isEmpty()) continue
            if (n.contains(t)) {
                if (t.length < 6 && !(a.isNotEmpty() && n.contains(a))) continue
                best = maxOf(best, 0.8 + (if (a.isNotEmpty() && n.contains(a)) 0.15 else 0.0))
            } else {
                best = maxOf(best, sim(stem, "$ar $ti") * 0.9)
            }
        }
        return best
    }

    fun pairScore(cArtist: String, cTitle: String, pairs: List<Pair<String, String>>): Double {
        var best = 0.0
        for ((ar, ti) in pairs) {
            val ts = sim(ti, cTitle)
            val s = if (ar.isNotEmpty()) 0.75 * ts + 0.25 * sim(ar, cArtist) else 0.9 * ts
            best = maxOf(best, s)
        }
        return best
    }

    private fun tokens(s: String): List<String> {
        val n = Normalizer.normalize(s, Normalizer.Form.NFKC).lowercase()
        return WORD.findAll(n).map { it.value }.filter { it.length >= 2 || it[0].code > 127 }.toList()
    }

    fun queryScore(cArtist: String, cTitle: String, query: String): Double {
        val cn = norm("$cArtist $cTitle")
        val qn = norm(query)
        if (cn.isEmpty() || qn.isEmpty()) return 0.0
        if (cn == qn) return 1.0
        val r = ratio(qn, cn)
        val qt = tokens(query)
        val tt = tokens(cTitle)
        if (qt.isEmpty() || tt.isEmpty()) return r
        val c1 = qt.filter { cn.contains(norm(it)) }.sumOf { it.length }.toDouble() / qt.sumOf { it.length }
        val c2 = tt.filter { qn.contains(norm(it)) }.sumOf { it.length }.toDouble() / tt.sumOf { it.length }
        return maxOf(0.6 * c1 + 0.4 * c2, r)
    }

    fun durFactor(cDur: Double, length: Double): Double {
        if (length <= 0.0 || cDur <= 0.0) return 0.7
        val d = kotlin.math.abs(cDur - length)
        return when {
            d <= 2 -> 1.0
            d <= 4 -> 0.85
            d <= 8 -> 0.5
            d <= 15 -> 0.2
            else -> 0.0
        }
    }
}

private fun JSONObject.str(k: String): String = if (isNull(k)) "" else optString(k, "")

private fun enc(vararg kv: Pair<String, String>): String =
    kv.joinToString("&") { URLEncoder.encode(it.first, "UTF-8") + "=" + URLEncoder.encode(it.second, "UTF-8") }

private fun <T, R> pmap(items: List<T>, fn: (T) -> R): List<R?> {
    val futures = items.map { x ->
        Net.pool.submit(Callable<R?> { try { fn(x) } catch (e: Exception) { null } })
    }
    return futures.map { try { it.get() } catch (e: Exception) { null } }
}

/** Searches the local lyrics folder, then LRCLIB, Kugou and NetEase. */
class Searcher(private val dir: File) {
    private val errors = AtomicInteger(0)

    private fun httpGet(url: String, headers: Map<String, String> = emptyMap()): String {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 8000
            c.readTimeout = 8000
            c.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android) lyrics-widget/2.0")
            for ((k, v) in headers) c.setRequestProperty(k, v)
            return c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }.removePrefix("﻿")
        } finally {
            c.disconnect()
        }
    }

    private fun getJson(url: String, headers: Map<String, String> = emptyMap()): Any? =
        try {
            JSONTokener(httpGet(url, headers)).nextValue()
        } catch (e: Exception) {
            errors.incrementAndGet()
            null
        }

    // ---- sources ----

    private fun lrclib(kws: List<String>, pairs: List<Pair<String, String>>): List<Meta> {
        val base = "https://lrclib.net/api/search?"
        val urls = ArrayList<String>()
        for ((ar, ti) in pairs.filter { it.first.isNotEmpty() }.take(2)) {
            urls.add(base + enc("track_name" to ti, "artist_name" to ar))
        }
        for (k in kws.take(4)) urls.add(base + enc("q" to k))
        val out = ArrayList<Meta>()
        val seen = HashSet<Long>()
        for (res in pmap(urls) { getJson(it) }) {
            val arr = res as? JSONArray ?: continue
            for (i in 0 until arr.length()) {
                val r = arr.optJSONObject(i) ?: continue
                val synced = r.str("syncedLyrics")
                if (synced.isEmpty() || !seen.add(r.optLong("id"))) continue
                out.add(
                    Meta("LRCLIB", r.str("artistName"), r.str("trackName"), r.str("albumName"),
                        r.optDouble("duration", 0.0)) { synced }
                )
            }
        }
        return out
    }

    private fun netease(kws: List<String>): List<Meta> {
        val head = mapOf("Referer" to "https://music.163.com/", "Cookie" to "appver=2.0.2")
        val results = pmap(kws.take(4)) { k ->
            val u = "https://music.163.com/api/search/get/web?" + enc(
                "csrf_token" to "", "hlpretag" to "", "hlposttag" to "", "s" to k,
                "type" to "1", "offset" to "0", "total" to "true", "limit" to "8"
            )
            (getJson(u, head) as? JSONObject)?.optJSONObject("result")?.optJSONArray("songs")
        }
        val out = ArrayList<Meta>()
        val seen = HashSet<Long>()
        for (songs in results) {
            if (songs == null) continue
            for (i in 0 until songs.length()) {
                val s = songs.optJSONObject(i) ?: continue
                val sid = s.optLong("id")
                if (!seen.add(sid)) continue
                val names = ArrayList<String>()
                val artists = s.optJSONArray("artists")
                if (artists != null) {
                    for (j in 0 until artists.length()) names.add(artists.optJSONObject(j)?.str("name") ?: "")
                }
                out.add(
                    Meta("NetEase", names.joinToString(", "), s.str("name"),
                        s.optJSONObject("album")?.str("name") ?: "",
                        s.optDouble("duration", 0.0) / 1000.0) {
                        val u = "https://music.163.com/api/song/lyric?" +
                            enc("id" to sid.toString(), "lv" to "1", "kv" to "1", "tv" to "-1")
                        (getJson(u, head) as? JSONObject)?.optJSONObject("lrc")?.str("lyric")
                    }
                )
            }
        }
        return out
    }

    private fun kugouLyric(h: String, k: String, dur: Double): String? {
        val u = "http://lyrics.kugou.com/search?" + enc(
            "ver" to "1", "man" to "yes", "client" to "pc", "keyword" to k,
            "hash" to h, "timelength" to (dur * 1000).toLong().toString()
        )
        val cands = (getJson(u) as? JSONObject)?.optJSONArray("candidates")
        val c = cands?.optJSONObject(0) ?: return null
        val u2 = "http://lyrics.kugou.com/download?" + enc(
            "ver" to "1", "client" to "pc", "id" to c.str("id"),
            "accesskey" to c.str("accesskey"), "fmt" to "lrc", "charset" to "utf8"
        )
        val content = (getJson(u2) as? JSONObject)?.str("content") ?: ""
        if (content.isEmpty()) return null
        return String(Base64.decode(content, Base64.DEFAULT), Charsets.UTF_8).removePrefix("﻿")
    }

    private fun kugou(kws: List<String>): List<Meta> {
        val results = pmap(kws.take(4)) { k ->
            val u = "http://mobilecdn.kugou.com/api/v3/search/song?" + enc(
                "format" to "json", "keyword" to k, "page" to "1", "pagesize" to "8", "showtype" to "1"
            )
            Pair(k, (getJson(u) as? JSONObject)?.optJSONObject("data")?.optJSONArray("info"))
        }
        val out = ArrayList<Meta>()
        val seen = HashSet<String>()
        for (res in results) {
            if (res == null) continue
            val k = res.first
            val info = res.second ?: continue
            for (i in 0 until info.length()) {
                val s = info.optJSONObject(i) ?: continue
                val h = s.str("hash")
                if (h.isEmpty() || !seen.add(h)) continue
                val dur = s.optDouble("duration", 0.0)
                out.add(
                    Meta("Kugou", s.str("singername"), s.str("songname"), s.str("album_name"), dur) {
                        kugouLyric(h, k, dur)
                    }
                )
            }
        }
        return out
    }

    // ---- public ----

    fun local(title: String, artist: String, query: String): List<Cand> {
        val pairs = if (query.isNotEmpty()) listOf(Pair("", query)) else Match.buildPairs(title, artist)
        val raw = if (query.isNotEmpty()) query else title
        val out = ArrayList<Cand>()
        val files = dir.listFiles { f -> f.isFile && f.name.lowercase().endsWith(".lrc") } ?: return out
        for (f in files) {
            val stem = f.nameWithoutExtension
            var sc = Match.localScore(stem, pairs, raw)
            if (query.isNotEmpty()) sc = maxOf(sc, Match.queryScore("", stem, query))
            if (sc < 0.75) continue
            val lrc = try { f.readText().removePrefix("﻿") } catch (e: Exception) { continue }
            if (!Lrc.synced(lrc)) continue
            out.add(Cand("local", "", stem, "", 0.0, 1.0 + sc, lrc, f.absolutePath))
        }
        return out.sortedByDescending { it.score }.take(14)
    }

    fun online(title: String, artist: String, length: Double, query: String): OnlineResult {
        try {
            errors.set(0)
            val pairs = if (query.isNotEmpty()) listOf(Pair("", query)) else Match.buildPairs(title, artist)
            val kws = Match.buildKeywords(pairs)

            val futs = listOf(
                Net.pool.submit(Callable { lrclib(kws, pairs) }),
                Net.pool.submit(Callable { kugou(kws) }),
                Net.pool.submit(Callable { netease(kws) })
            )
            val metas = ArrayList<Meta>()
            for (f in futs) {
                try { metas.addAll(f.get()) } catch (e: Exception) { /* a source failed */ }
            }

            for (m in metas) {
                m.score = if (query.isNotEmpty()) {
                    Match.queryScore(m.artist, m.title, query)
                } else {
                    Match.pairScore(m.artist, m.title, pairs) * (0.5 + 0.5 * Match.durFactor(m.duration, length))
                }
            }
            // A typed query can be for another song: playing duration only breaks ties.
            val metaOrder = compareByDescending<Meta> { it.score }
                .thenByDescending { if (query.isNotEmpty()) Match.durFactor(it.duration, length) else 0.0 }

            val sorted = metas.filter { it.score >= 0.3 }.sortedWith(metaOrder)
            val perSource = HashMap<String, Int>()
            val chosen = ArrayList<Meta>()
            for (m in sorted) {
                val n = perSource[m.source] ?: 0
                if (n >= 5) continue
                perSource[m.source] = n + 1
                chosen.add(m)
            }

            val fetched = pmap(chosen) { it.fetch() }
            val seenLrc = HashSet<Int>()
            val cands = ArrayList<Cand>()
            for ((i, m) in chosen.withIndex()) {
                val lrc = fetched[i]
                if (lrc == null || !Lrc.synced(lrc) || !seenLrc.add(lrc.hashCode())) continue
                cands.add(Cand(m.source, m.artist, m.title, m.album, m.duration, Math.round(m.score * 1000) / 1000.0, lrc, ""))
            }
            val candOrder = compareByDescending<Cand> { it.score }
                .thenByDescending { if (query.isNotEmpty()) Match.durFactor(it.duration, length) else 0.0 }
            return OnlineResult(cands.sortedWith(candOrder).take(14), errors.get(), false)
        } catch (e: Exception) {
            return OnlineResult(emptyList(), errors.get(), true)
        }
    }
}
