package com.lyricswidget.app

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** Follows the active media session (Spotify, YouTube Music, browsers...) and feeds [LyricsStore]. */
class MediaTracker(ctx: Context) {
    private val msm = ctx.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val listener = ComponentName(ctx, LyricsService::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var attached: MediaController? = null
    private var meta: MediaMetadata? = null
    private var state: PlaybackState? = null

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        repick(list)
    }

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            meta = metadata
            publish()
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            this@MediaTracker.state = state
            publish()
        }

        override fun onSessionDestroyed() {
            poll(false)
        }
    }

    fun start() {
        if (running) return
        running = true
        try {
            msm.addOnActiveSessionsChangedListener(sessionsListener, listener, handler)
        } catch (e: SecurityException) {
            // Notification access not granted yet.
        }
        poll(true)
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        try { msm.removeOnActiveSessionsChangedListener(sessionsListener) } catch (e: Exception) { }
        detach()
        LyricsStore.noPlayer()
    }

    private fun poll(loop: Boolean) {
        if (!running) return
        val list = try {
            msm.getActiveSessions(listener)
        } catch (e: SecurityException) {
            emptyList<MediaController>()
        }
        repick(list)
        if (loop) handler.postDelayed({ poll(true) }, 1500)
    }

    private fun isPlaying(c: MediaController): Boolean {
        val s = c.playbackState?.state
        return s == PlaybackState.STATE_PLAYING || s == PlaybackState.STATE_BUFFERING
    }

    private fun repick(list: List<MediaController>?) {
        val l = list ?: emptyList()
        val best = l.firstOrNull { isPlaying(it) }
            ?: l.firstOrNull { it.sessionToken == attached?.sessionToken }
            ?: l.firstOrNull()
        if (best == null) {
            detach()
            LyricsStore.noPlayer()
            return
        }
        if (attached?.sessionToken != best.sessionToken) attach(best)
    }

    private fun attach(c: MediaController) {
        detach()
        attached = c
        c.registerCallback(callback, handler)
        meta = c.metadata
        state = c.playbackState
        LyricsStore.transport = c.transportControls
        publish()
    }

    private fun detach() {
        try { attached?.unregisterCallback(callback) } catch (e: Exception) { }
        attached = null
        meta = null
        state = null
        LyricsStore.transport = null
    }

    private fun publish() {
        if (attached == null) return
        val m = meta
        val title = m?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: ""
        val artist = m?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: m?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE) ?: ""
        val art = m?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: m?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: m?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        val dur = (m?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L) / 1000.0

        var known = false
        var pos = 0.0
        var playing = false
        var speed = 1.0
        val s = state
        if (s != null) {
            playing = s.state == PlaybackState.STATE_PLAYING
            known = s.position >= 0
            if (s.playbackSpeed > 0f) speed = s.playbackSpeed.toDouble()
            if (known) {
                pos = s.position / 1000.0
                if (playing) pos += (SystemClock.elapsedRealtime() - s.lastPositionUpdateTime) / 1000.0 * speed
            }
        }
        if (dur > 0.0) pos = minOf(pos, dur)
        LyricsStore.onMedia(title.isNotEmpty(), title, artist, art, dur, pos, known, playing, speed)
    }
}
