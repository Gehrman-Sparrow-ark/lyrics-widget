package com.lyricswidget.app

/** Overlay visibility policy, independent of Android's media callbacks and window APIs. */
internal class OverlayVisibility {
    private var opened = false
    private var pausedSince: Long? = null

    fun showNow() { opened = true }

    fun reset() {
        opened = false
        pausedSince = null
    }

    fun shouldShow(
        now: Long,
        enabled: Boolean,
        canDraw: Boolean,
        dismissed: Boolean,
        hasTrack: Boolean,
        playbackActive: Boolean,
        hasLyricsOrLoading: Boolean,
        hideNoLyrics: Boolean,
        hideWhenPaused: Boolean
    ): Boolean {
        if (!enabled || !canDraw) {
            reset()
            return false
        }
        if (playbackActive || !hasTrack || !hideWhenPaused) pausedSince = null
        else if (pausedSince == null) pausedSince = now

        if (dismissed) {
            reset()
            return false
        }
        if (hasTrack || playbackActive) opened = true
        if (!opened) return false
        if (hasTrack && hideNoLyrics && !hasLyricsOrLoading) return false
        if (playbackActive) return true
        if (!hasTrack && hideWhenPaused) return false
        return pausedSince?.let { now - it < 8_000L } ?: true
    }
}
