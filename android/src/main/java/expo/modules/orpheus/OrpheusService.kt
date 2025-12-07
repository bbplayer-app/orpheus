package expo.modules.orpheus

import android.os.Bundle
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import expo.modules.orpheus.bilibili.BilibiliRepository
import expo.modules.orpheus.utils.MediaItemStorer
import expo.modules.orpheus.utils.SleepTimeController
import java.io.IOException

class OrpheusService : MediaLibraryService() {

    private var player: ExoPlayer? = null
    private var mediaSession: MediaLibrarySession? = null
    private var sleepTimerManager: SleepTimeController? = null

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()

        MediaItemStorer.initialize(this)


        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")
            .setAllowCrossProtocolRedirects(true)

        val cacheDataSourceFactory = CacheDataSource.Factory()
            .setCache(DownloadCache.get(this))
            .setUpstreamDataSourceFactory(httpDataSourceFactory)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

        val resolvingDataSourceFactory = ResolvingDataSource.Factory(
            cacheDataSourceFactory,
            object : ResolvingDataSource.Resolver {
                // TODO: maybe we need to add a cache?
                override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
                    val uri = dataSpec.uri

                    // orpheus://bilibili?bvid=bv123124&cid=114514&quality=30280&dolby=0&hires=0
                    if (uri.scheme == "orpheus" && uri.host == "bilibili") {
                        try {
                            val bvid = uri.getQueryParameter("bvid")
                            val cid = uri.getQueryParameter("cid")?.toLongOrNull()
                            val quality = uri.getQueryParameter("quality")?.toIntOrNull() ?: 30280
                            val enableDolby = uri.getQueryParameter("dolby") == "1"
                            val enableHiRes = uri.getQueryParameter("hires") == "1"

                            if (bvid == null) {
                                throw IOException("Invalid Bilibili Params: bvid=$bvid, cid=$cid")
                            }

                            val realUrl = BilibiliRepository.resolveAudioUrl(
                                bvid = bvid,
                                cid = cid,
                                audioQuality = quality,
                                enableDolby = enableDolby,
                                enableHiRes = enableHiRes,
                                cookie = OrpheusConfig.bilibiliCookie
                            )

                            val headers = HashMap<String, String>()
                            headers["Referer"] = "https://www.bilibili.com/"

                            return dataSpec.buildUpon()
                                .setUri(realUrl.toUri())
                                .setHttpRequestHeaders(headers)
                                .setKey(uri.toString())
                                .build()
                        } catch (e: Exception) {
                            throw IOException("Resolve Url Failed: ${e.message}", e)
                        }
                    }

                    return dataSpec
                }
            }
        )

        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(resolvingDataSourceFactory)

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

        mediaSession = MediaLibrarySession.Builder(this, player!!, callback)
            .setId("OrpheusSession")
            .build()

        restorePlayerState(MediaItemStorer.isRestoreEnabled())
        sleepTimerManager = SleepTimeController(player!!)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? {
        return mediaSession
    }

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }

    var callback: MediaLibrarySession.Callback = @UnstableApi
    object : MediaLibrarySession.Callback {
        private val customCommands = listOf(
            SessionCommand(CustomCommands.CMD_START_TIMER, Bundle.EMPTY),
            SessionCommand(CustomCommands.CMD_CANCEL_TIMER, Bundle.EMPTY),
            SessionCommand(CustomCommands.CMD_GET_REMAINING, Bundle.EMPTY)
        )

        @OptIn(UnstableApi::class)
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            val availableCommandsBuilder =
                MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()

            for (command in customCommands) {
                availableCommandsBuilder.add(command)
            }

            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(availableCommandsBuilder.build())
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle
        ): ListenableFuture<SessionResult> {

            Log.d("Orpheus", "onCustomCommand: ${customCommand.customAction}")

            when (customCommand.customAction) {
                CustomCommands.CMD_START_TIMER -> {
                    val durationMs = args.getLong(CustomCommands.KEY_DURATION)
                    sleepTimerManager?.start(durationMs)
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }

                CustomCommands.CMD_CANCEL_TIMER -> {
                    sleepTimerManager?.cancel()
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }

                CustomCommands.CMD_GET_REMAINING -> {
                    val stopTime = sleepTimerManager?.getStopTimeMs()
                    val resultBundle = Bundle()
                    if (stopTime != null) {
                        resultBundle.putLong(CustomCommands.KEY_STOP_TIME, stopTime)
                    }

                    return Futures.immediateFuture(
                        SessionResult(
                            SessionResult.RESULT_SUCCESS,
                            resultBundle
                        )
                    )
                }
            }

            return super.onCustomCommand(session, controller, customCommand, args)
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

        val restoredItems = MediaItemStorer.restoreQueue()

        if (restoredItems.isNotEmpty()) {
            player.setMediaItems(restoredItems)

            val savedIndex = MediaItemStorer.getSavedIndex()
            val savedPosition = MediaItemStorer.getSavedPosition()

            if (savedIndex >= 0 && savedIndex < restoredItems.size) {
                player.seekTo(savedIndex, if (restorePosition) savedPosition else C.TIME_UNSET)
            } else {
                player.seekTo(0, 0L)
            }

            player.playWhenReady = false
            player.prepare()
        }
    }

    private fun setupListeners() {
        player?.addListener(object : Player.Listener {
            override fun onMediaItemTransition(
                mediaItem: androidx.media3.common.MediaItem?,
                reason: Int
            ) {
                saveCurrentQueue()
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
            MediaItemStorer.saveQueue(queue)
        }
    }
}
