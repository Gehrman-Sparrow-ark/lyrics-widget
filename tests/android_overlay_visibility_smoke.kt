package com.lyricswidget.app

fun main() {
    val visibility = OverlayVisibility()
    fun visible(
        time: Long,
        track: Boolean = false,
        active: Boolean = false,
        lyrics: Boolean = false,
        hideNoLyrics: Boolean = false,
        hidePaused: Boolean = false,
        enabled: Boolean = true,
        canDraw: Boolean = true,
        dismissed: Boolean = false
    ) = visibility.shouldShow(time, enabled, canDraw, dismissed, track, active,
        lyrics, hideNoLyrics, hidePaused)

    check(!visible(0))
    check(visible(1, active = true, hideNoLyrics = true))
    check(visible(2, track = true, active = true, lyrics = true, hideNoLyrics = true))
    check(!visible(3, track = true, active = true, hideNoLyrics = true))
    check(visible(4)) // Media session disappears while the screen is locked.
    check(visible(5, track = true, hidePaused = true))
    check(!visible(8005, track = true, hidePaused = true))
    check(visible(8006, track = true, active = true, hidePaused = true))
    check(!visible(8007, track = true, active = true, dismissed = true))
    check(!visible(8008, active = true, dismissed = true)) // New playback does not reopen after X.
    visibility.showNow()
    check(visible(10_002))
    check(visible(25_000))
    check(!visible(30_001, enabled = false))
    check(!visible(30_002))
    visibility.showNow()
    check(!visible(31_001, canDraw = false))
    check(!visible(31_002))
    println("PASS: playback before metadata, lyrics loading, keep-open, explicit close, and manual reopen")
}
