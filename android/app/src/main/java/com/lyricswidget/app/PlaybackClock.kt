package com.lyricswidget.app

/** MediaSession's update time is elapsed realtime; zero means no update timestamp. */
internal fun estimatePosition(positionMs: Long, updatedMs: Long, nowMs: Long,
                              playing: Boolean, speed: Double): Double {
    val elapsed = if (playing && updatedMs > 0 && updatedMs <= nowMs) nowMs - updatedMs else 0L
    return positionMs / 1000.0 + elapsed / 1000.0 * speed
}
