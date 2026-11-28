package com.lyricswidget.app

import kotlin.math.abs

fun main() {
    val wave = LyricWaveMotion
    fun near(actual: Float, expected: Float) = check(abs(actual - expected) < 0.001f) {
        "expected $expected but was $actual"
    }

    check(wave.canGlide(2, 3, 5))
    check(wave.canGlide(3, 2, 5))
    check(!wave.canGlide(0, 3, 5))
    check(wave.canGlide(-1, 0, 5))
    check(!wave.canGlide(-1, 0, 0))
    check(!wave.canGlide(3, 4, 4))
    check(!wave.canGlide(1, 1, 5))

    // Both lyric identities stay on their own continuous, symmetric paths.
    for (step in 0..100) {
        val progress = step / 100f
        val leaving = wave.offset(-progress, 40f, 28f)
        val entering = wave.offset(1f - progress, 40f, 28f)
        near(entering - leaving, 34f)
        near(wave.emphasis(progress) + wave.emphasis(1f - progress), 1f)
        for (radius in 0..2) {
            check(wave.opacity(progress, radius) in 0f..1f)
            check(wave.opacity(1f - progress, radius) in 0f..1f)
            check(wave.opacity(0.5f, radius) > 0f)
            near(wave.opacity((radius + 1).toFloat(), radius), 0f)
        }
    }
    near(wave.offset(2f, 40f, 28f), 62f)
    near(wave.opacity(0f, 2), 1f)
    near(wave.opacity(1f, 2), 0.6f)
    near(wave.opacity(2f, 2), 0.3f)
    println("Android lyric wave checks passed")
}
