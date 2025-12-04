package expo.modules.orpheus

import android.content.ComponentName
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.google.gson.Gson
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoOrpheusModule : Module() {
    companion object {
        val TAG = "Orpheus"
    }

    private var controllerFuture: ListenableFuture<MediaController>? = null

    private var controller: MediaController? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // 记录上一首歌曲的 ID，用于在切歌时发送给 JS
    private var lastMediaId: String? = null

    val gson = Gson()

    override fun definition() = ModuleDefinition {
        Name("Orpheus")

        Events(
            "onPlaybackStateChanged",
            "onTrackTransition",
            "onPlayerError",
            "onPositionUpdate",
            "onIsPlayingChanged"
        )

        OnCreate {
            val context = appContext.reactContext ?: return@OnCreate
            val sessionToken = SessionToken(
                context,
                ComponentName(context, OrpheusService::class.java)
            )
            controllerFuture = MediaController.Builder(context, sessionToken)
                .setApplicationLooper(Looper.getMainLooper()).buildAsync()

            controllerFuture?.addListener({
                try {
                    controller = controllerFuture?.get()
                    setupListeners()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }, MoreExecutors.directExecutor())
        }

        OnDestroy {
            stopProgressUpdater()
            controllerFuture?.let { MediaController.releaseFuture(it) }
        }

        AsyncFunction("getPosition") {
            controller?.currentPosition?.toDouble()?.div(1000.0) ?: 0.0
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getDuration") {
            val d = controller?.duration ?: C.TIME_UNSET
            if (d == C.TIME_UNSET) 0.0 else d.toDouble() / 1000.0
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getIsPlaying") {
            controller?.isPlaying ?: false
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getCurrentIndex") {
            controller?.currentMediaItemIndex ?: -1
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getCurrentTrack") {
            val player = controller ?: return@AsyncFunction null
            val currentItem = player.currentMediaItem ?: return@AsyncFunction null

            mediaItemToTrackRecord(currentItem)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getShuffleMode") {
            controller?.shuffleModeEnabled
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getIndexTrack") { index: Int ->
            controller?.getMediaItemAt(index)
        }.runOnQueue(Queues.MAIN)

        Function("setBilibiliCookie") { cookie: String ->
            OrpheusConfig.bilibiliCookie = cookie
        }

        AsyncFunction("play") {
            val player = controller
            if (player != null) {
                // 获取 player 真正归属的 Looper
                val playerLooper = player.applicationLooper

                if (Looper.myLooper() == playerLooper) {
                    player.play()
                } else {
                    Handler(playerLooper).post {
                        player.play()
                    }
                }
            }
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("pause") {
            controller?.pause()
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("clear") {
            controller?.clearMediaItems()
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("skipTo") { index: Int ->
            // 跳转到指定索引的开头
            controller?.seekTo(index, C.TIME_UNSET)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("skipToNext") {
            if (controller?.hasNextMediaItem() == true) {
                controller?.seekToNextMediaItem()
            }
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("skipToPrevious") {
            if (controller?.hasPreviousMediaItem() == true) {
                controller?.seekToPreviousMediaItem()
            }
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("seekTo") { seconds: Double ->
            val ms = (seconds * 1000).toLong()
            controller?.seekTo(ms)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("setRepeatMode") { mode: Int ->
            // mode: 0=OFF, 1=TRACK, 2=QUEUE
            val repeatMode = when (mode) {
                1 -> Player.REPEAT_MODE_ONE
                2 -> Player.REPEAT_MODE_ALL
                else -> Player.REPEAT_MODE_OFF
            }
            controller?.repeatMode = repeatMode
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("setShuffleMode") { enabled: Boolean ->
            controller?.shuffleModeEnabled = enabled
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getQueue") {
            val player = controller ?: return@AsyncFunction emptyList<TrackRecord>()
            val count = player.mediaItemCount
            val queue = ArrayList<TrackRecord>(count)

            for (i in 0 until count) {
                val item = player.getMediaItemAt(i)
                queue.add(mediaItemToTrackRecord(item))
            }

            return@AsyncFunction queue
        }

        AsyncFunction("add") { tracks: List<TrackRecord> ->
            // 1. 【后台线程】执行：JSON 转换、Metadata 构建 (耗时操作在这里做，不卡 UI)
            // 这里不需要改，继续在当前线程跑
            val mediaItems = tracks.mapNotNull { track ->
                try {
                    val trackJson = gson.toJson(track)
                    val extras = Bundle()
                    extras.putString("track_json", trackJson)

                    val artUri =
                        if (!track.artwork.isNullOrEmpty()) track.artwork!!.toUri() else null

                    val metadata = MediaMetadata.Builder()
                        .setTitle(track.title)
                        .setArtist(track.artist)
                        .setArtworkUri(artUri)
                        .setExtras(extras)
                        .build()

                    MediaItem.Builder()
                        .setMediaId(track.id)
                        .setUri(track.url ?: "")
                        .setMediaMetadata(metadata)
                        .build()
                } catch (e: Exception) {
                    e.printStackTrace()
                    null
                }
            }

            val player = controller
            if (player != null) {
                // 获取 player 真正归属的 Looper
                val playerLooper = player.applicationLooper

                if (Looper.myLooper() == playerLooper) {
                    player.addMediaItems(mediaItems)
                    if (player.playbackState == Player.STATE_IDLE) {
                        player.prepare()
                    }
                } else {
                    Handler(playerLooper).post {
                        player.addMediaItems(mediaItems)
                        if (player.playbackState == Player.STATE_IDLE) {
                            player.prepare()
                        }
                    }
                }
            }
        }
    }

    private fun setupListeners() {
        controller?.addListener(object : Player.Listener {

            /**
             * 核心：处理切歌、播放结束逻辑
             */
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val currentTrackId = mediaItem?.mediaId ?: ""
                Player.MEDIA_ITEM_TRANSITION_REASON_AUTO

                sendEvent(
                    "onTrackTransition", mapOf(
                        "currentTrackId" to currentTrackId,
                        "previousTrackId" to lastMediaId, // 上一首歌是什么
                        "reason" to reason
                    )
                )

                // 更新本地记录，为下一次切歌做准备
                lastMediaId = currentTrackId
            }

            /**
             * 处理播放状态改变
             */
            override fun onPlaybackStateChanged(state: Int) {
                // state: 1=IDLE, 2=BUFFERING, 3=READY, 4=ENDED
                sendEvent(
                    "onPlaybackStateChanged", mapOf(
                        "state" to state
                    )
                )

                updateProgressRunnerState()
            }

            /**
             * 处理播放/暂停状态
             */
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                sendEvent(
                    "onIsPlayingChanged", mapOf(
                        "status" to isPlaying
                    )
                )
                updateProgressRunnerState()
            }

            /**
             * 处理错误
             */
            override fun onPlayerError(error: PlaybackException) {
                sendEvent(
                    "onPlayerError", mapOf(
                        "code" to error.errorCode.toString(),
                        "message" to (error.message ?: "Unknown Error")
                    )
                )
            }
        })
    }

    private val progressRunnable = object : Runnable {
        override fun run() {
            val player = controller ?: return

            if (player.isPlaying) {
                val currentMs = player.currentPosition
                val durationMs = player.duration

                sendEvent(
                    "onPositionUpdate", mapOf(
                        "position" to currentMs / 1000.0,
                        "duration" to if (durationMs == C.TIME_UNSET) 0.0 else durationMs / 1000.0,
                        "buffered" to player.bufferedPosition / 1000.0
                    )
                )
            }

            mainHandler.postDelayed(this, 200)
        }
    }

    private fun updateProgressRunnerState() {
        val player = controller
        // 如果正在播放且状态是 READY，则开始轮询
        if (player != null && player.isPlaying && player.playbackState == Player.STATE_READY) {
            startProgressUpdater()
        } else {
            stopProgressUpdater()
        }
    }

    private fun startProgressUpdater() {
        mainHandler.removeCallbacks(progressRunnable)
        mainHandler.post(progressRunnable)
    }

    private fun stopProgressUpdater() {
        mainHandler.removeCallbacks(progressRunnable)
    }

    private fun mediaItemToTrackRecord(item: MediaItem): TrackRecord {
        val extras = item.mediaMetadata.extras
        val trackJson = extras?.getString("track_json")

        if (trackJson != null) {
            try {
                return gson.fromJson(trackJson, TrackRecord::class.java)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        val track = TrackRecord()
        track.id = item.mediaId
        track.url = item.localConfiguration?.uri?.toString() ?: ""
        track.title = item.mediaMetadata.title?.toString()
        track.artist = item.mediaMetadata.artist?.toString()
        track.artwork = item.mediaMetadata.artworkUri?.toString()

        return track
    }
}