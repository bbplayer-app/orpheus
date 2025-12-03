package expo.modules.orpheus

import android.content.ComponentName
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
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
            controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()

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

        Property("position") {
            controller?.currentPosition?.toDouble()?.div(1000.0) ?: 0.0
        }

        Property("duration") {
            val d = controller?.duration ?: C.TIME_UNSET
            if (d == C.TIME_UNSET) 0.0 else d.toDouble() / 1000.0
        }

        Property("isPlaying") {
            controller?.isPlaying ?: false
        }

        Property("currentIndex") {
            controller?.currentMediaItemIndex ?: -1
        }

        Property("currentTrack") {
            val player = controller ?: return@Property null
            val currentItem = player.currentMediaItem ?: return@Property null

            mediaItemToTrackRecord(currentItem)
        }

        Property("shuffleMode") {
            controller?.shuffleModeEnabled
        }

        Function("getIndexTrack") { index: Int ->
            controller?.getMediaItemAt(index)
        }

        Function("setBilibiliCookie") { cookie: String ->
            OrpheusConfig.bilibiliCookie = cookie
        }

        Function("play") {
            controller?.play()
        }

        Function("pause") {
            controller?.pause()
        }

        Function("clear") {
            controller?.clearMediaItems()
        }

        Function("skipTo") { index: Int ->
            // 跳转到指定索引的开头
            controller?.seekTo(index, C.TIME_UNSET)
        }

        Function("skipToNext") {
            if (controller?.hasNextMediaItem() == true) {
                controller?.seekToNextMediaItem()
            }
        }

        Function("skipToPrevious") {
            if (controller?.hasPreviousMediaItem() == true) {
                controller?.seekToPreviousMediaItem()
            }
        }

        Function("seekTo") { seconds: Double ->
            val ms = (seconds * 1000).toLong()
            controller?.seekTo(ms)
        }

        Function("setRepeatMode") { mode: Int ->
            // mode: 0=OFF, 1=TRACK, 2=QUEUE
            val repeatMode = when (mode) {
                1 -> Player.REPEAT_MODE_ONE
                2 -> Player.REPEAT_MODE_ALL
                else -> Player.REPEAT_MODE_OFF
            }
            controller?.repeatMode = repeatMode
        }

        Function("setShuffleMode") { enabled: Boolean ->
            controller?.shuffleModeEnabled = enabled
        }

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
            Log.e(TAG, "add ${tracks.size} to media")

            val player = controller
            if (player == null) {
                Log.e("Orpheus", "❌ 严重错误: Controller 为 null！Service 可能没启动或连接失败。")
                // 抛出错误让 JS 端能 catch 到
                throw IllegalStateException("Controller is not ready yet!")
            }
            try {
                val mediaItems = tracks.map { track ->
                    Log.e(TAG, "0")
                    val trackJson = gson.toJson(track)

                    val extras = Bundle()
                    Log.e(TAG, "1")
                    extras.putString("track_json", trackJson)
                    val metadata = MediaMetadata.Builder()
                        .setTitle(track.title)
                        .setArtist(track.artist)
                        .setArtworkUri(if (track.artwork != null) track.artwork!!.toUri() else null)
                        .setExtras(extras)
                        .build()
                    Log.e(TAG, "2")
                    MediaItem.Builder()
                        .setMediaId(track.id)
                        .setUri(track.url)
                        .setMediaMetadata(metadata)
                        .build()
                }

                Log.d("Orpheus", "✅ 成功添加到播放器，当前状态: ${player.playbackState}")
                controller?.addMediaItems(mediaItems)
                if (controller?.playbackState == Player.STATE_IDLE) {
                    controller?.prepare()
                }

                Log.e(TAG, controller?.mediaItemCount.toString())
            } catch (e: Error) {
                Log.e(TAG, e.toString())
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