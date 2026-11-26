package com.lyricswidget.app

data class Line(val t: Double, val text: String)

object Lrc {
    private val TIME = Regex("""\[(\d+):(\d+(?:[.:]\d+)?)]""")
    private val OFFSET = Regex("""^\[offset:\s*([+-]?\d+)\s*]""", RegexOption.IGNORE_CASE)
    private val OFFSET_LINE = Regex("""^\[offset:[^\]]*][ \t]*\r?\n?""", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
    private val STAMP_START = Regex("""^\[\d+:\d+""", RegexOption.MULTILINE)

    /** Returns the timed lines and the [offset:] value in milliseconds. */
    fun parse(text: String): Pair<List<Line>, Int> {
        val out = ArrayList<Line>()
        var off = 0
        for (raw in text.split("\n")) {
            val l = raw.trimEnd('\r')
            val om = OFFSET.find(l)
            if (om != null) {
                off = om.groupValues[1].toIntOrNull() ?: 0
                continue
            }
            val matches = TIME.findAll(l).toList()
            if (matches.isEmpty()) continue
            val txt = l.substring(matches.last().range.last + 1).trim()
            for (m in matches) {
                val t = m.groupValues[1].toInt() * 60 + m.groupValues[2].replace(':', '.').toDouble()
                out.add(Line(t, txt))
            }
        }
        out.sortBy { it.t }
        return Pair(out, off)
    }

    fun synced(lrc: String?): Boolean = lrc != null && STAMP_START.findAll(lrc).count() >= 3

    fun withOffset(lrc: String, offMs: Int): String {
        val clean = OFFSET_LINE.replace(lrc, "")
        return if (offMs != 0) "[offset:$offMs]\n$clean" else clean
    }

    fun safeName(artist: String, title: String): String {
        val raw = if (artist.isNotEmpty()) "$artist - $title" else title
        var name = raw
            .replace(Regex("""[\\/:*?"<>|\u0000-\u001f]"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim(' ', '.')
        while (name.toByteArray(Charsets.UTF_8).size > 200) name = name.dropLast(1)
        return if (name.isEmpty()) "untitled" else name
    }
}
