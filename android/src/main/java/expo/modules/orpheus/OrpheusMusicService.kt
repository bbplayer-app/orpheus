package expo.modules.orpheus

import android.app.PendingIntent
import android.content.Intent
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import expo.modules.orpheus.bilibili.VolumeData
import expo.modules.orpheus.utils.DownloadUtil
import expo.modules.orpheus.utils.SleepTimeController
import expo.modules.orpheus.utils.Storage
import expo.modules.orpheus.utils.calculateLoudnessGain
import expo.modules.orpheus.utils.fadeInTo
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlin.math.abs

class OrpheusMusicService : MediaLibraryService() {

    var player: ExoPlayer? = null
    private var mediaSession: MediaLibrarySession? = null
    private var sleepTimerManager: SleepTimeController? = null
    private var volumeFadeJob: Job? = null
    private var scope = MainScope()

    companion object {
        var instance: OrpheusMusicService? = null
            private set(value) {
                field = value
                if (value != null) {
                    listeners.forEach { it(value) }
                }
            }

        private val listeners = mutableListOf<(OrpheusMusicService) -> Unit>()

        fun addOnServiceReadyListener(listener: (OrpheusMusicService) -> Unit) {
            instance?.let { listener(it) }
            listeners.add(listener)
        }

        fun removeOnServiceReadyListener(listener: (OrpheusMusicService) -> Unit) {
            listeners.remove(listener)
        }
    }

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        instance = this

        Storage.initialize(this)


        val dataSourceFactory = DownloadUtil.getPlayerDataSourceFactory(this)

        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(dataSourceFactory)


        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true
            )
            .build()

        setupListeners()

        var launchIntent = packageManager.getLaunchIntentForPackage(packageName)

        if (launchIntent == null) {
            launchIntent = Intent().apply {
                setClassName(packageName, "$packageName.MainActivity")
            }
        }

        launchIntent.apply {
            action = Intent.ACTION_VIEW
            data = "orpheus://player".toUri()
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val contentIntent = launchIntent.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        mediaSession = MediaLibrarySession.Builder(this, player!!, callback)
            .setId("OrpheusSession")
            .setSessionActivity(contentIntent)
            .build()

        restorePlayerState(Storage.isRestoreEnabled())
        sleepTimerManager = SleepTimeController(player!!)

        // 当有新的响度数据时，如果是当前这首歌的就直接应用，否则是预加载，等待 onMediaItemTransition 处理
        scope.launch {
            DownloadUtil.volumeResolvedEvent.collect { (uri, volumeData) ->
                val currentUri = player?.currentMediaItem?.localConfiguration?.uri?.toString()
                if (currentUri == uri) {
                    applyVolumeForCurrentItem(volumeData)
                }
            }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? {
        return mediaSession
    }

    override fun onDestroy() {
        scope.cancel()
        instance = null

        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }

    fun startSleepTimer(durationMs: Long) {
        sleepTimerManager?.start(durationMs)
    }

    fun cancelSleepTimer() {
        sleepTimerManager?.cancel()
    }

    fun getSleepTimerRemaining(): Long? {
        return sleepTimerManager?.getStopTimeMs()
    }

    var callback: MediaLibrarySession.Callback = @UnstableApi
    object : MediaLibrarySession.Callback {

        @OptIn(UnstableApi::class)
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .build()
        }

        /**
         * 修复 UnsupportedOperationException 的关键！
         * 当系统尝试恢复播放（比如从“最近播放”卡片点击）时触发。
         */
        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(
                    emptyList(), // 没有媒体项
                    C.INDEX_UNSET, // 索引未定
                    C.TIME_UNSET   // 进度未定
                )
            )
        }
    }

    @OptIn(UnstableApi::class)
    private fun restorePlayerState(restorePosition: Boolean) {
        val player = player ?: return

        val restoredItems = Storage.restoreQueue()

        if (restoredItems.isNotEmpty()) {
            player.setMediaItems(restoredItems)

            val savedIndex = Storage.getSavedIndex()
            val savedPosition = Storage.getSavedPosition()
            val savedShuffleMode = Storage.getShuffleMode()
            val savedRepeatMode = Storage.getRepeatMode()

            if (savedIndex >= 0 && savedIndex < restoredItems.size) {
                player.seekTo(savedIndex, if (restorePosition) savedPosition else C.TIME_UNSET)
            } else {
                player.seekTo(0, 0L)
            }

            player.shuffleModeEnabled = savedShuffleMode
            player.repeatMode = savedRepeatMode

            player.playWhenReady = false
            player.prepare()
        }
    }

    private fun setupListeners() {
        player?.addListener(object : Player.Listener {
            @OptIn(UnstableApi::class)
            override fun onMediaItemTransition(
                mediaItem: androidx.media3.common.MediaItem?,
                reason: Int
            ) {
                saveCurrentQueue()
                val uri = mediaItem?.localConfiguration?.uri?.toString() ?: return

                val volumeData = DownloadUtil.itemVolumeMap[uri]
                if (volumeData != null) {
                    applyVolumeForCurrentItem(volumeData)
                }
            }

            override fun onTimelineChanged(timeline: Timeline, reason: Int) {
                saveCurrentQueue()
            }
        })
    }

    private fun saveCurrentQueue() {
        val player = player ?: return
        val queue = List(player.mediaItemCount) { i -> player.getMediaItemAt(i) }
        if (queue.isNotEmpty()) {
            Storage.saveQueue(queue)
        }
    }

    @OptIn(UnstableApi::class)
    private fun applyVolumeForCurrentItem(volumeData: VolumeData) {
        val player = player ?: return
        volumeFadeJob?.cancel()
        val isLoudnessNormalizationEnabled = Storage.isLoudnessNormalizationEnabled()
        if (!isLoudnessNormalizationEnabled) return
        val gain = run {
            val measured = volumeData.measuredI
            val target = volumeData.targetI

            if (measured == 0.0) 1.0f else calculateLoudnessGain(measured, target)
        }

        val targetVol = 1.0f * gain
        val currentVolume = player.volume

        if (abs(currentVolume - targetVol) < 0.001f) {
            return
        }

        volumeFadeJob = player.fadeInTo(targetVol, 600L, scope)
    }
}
