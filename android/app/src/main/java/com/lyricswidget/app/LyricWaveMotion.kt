package com.lyricswidget.app

import kotlin.math.abs
import kotlin.math.sign

/** Geometry of the lyric viewport in line coordinates (zero is the active row). */
internal object LyricWaveMotion {
    const val DURATION_MS = 450L
    const val RETARGET_MS = 240L

    fun canGlide(oldIndex: Int, newIndex: Int, count: Int): Boolean =
        oldIndex in -1 until count && newIndex in 0 until count && abs(newIndex - oldIndex) == 1

    fun offset(relative: Float, centerHeight: Float, sideHeight: Float): Float {
        val distance = abs(relative)
        val firstGap = (centerHeight + sideHeight) / 2f
        return sign(relative) * if (distance <= 1f) {
            firstGap * distance
        } else {
            firstGap + sideHeight * (distance - 1f)
        }
    }

    fun emphasis(distance: Float): Float = (1f - distance).coerceIn(0f, 1f)

    fun opacity(distance: Float, radius: Int): Float {
        val edge = (radius + 1 - distance).coerceIn(0f, 1f)
        val base = if (distance <= 1f) {
            1f - 0.4f * distance
        } else {
            0.6f - 0.3f * (distance - 1f).coerceIn(0f, 1f)
        }
        return base * edge
    }
}
