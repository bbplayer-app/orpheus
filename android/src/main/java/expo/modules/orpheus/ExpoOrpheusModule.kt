package expo.modules.orpheus

import android.content.ComponentName
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.google.gson.Gson
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.orpheus.models.TrackRecord
import expo.modules.orpheus.utils.MediaItemStorer
import expo.modules.orpheus.utils.toMediaItem

class ExpoOrpheusModule : Module() {
    private var controllerFuture: ListenableFuture<MediaController>? = null

    private var controller: MediaController? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // 记录上一首歌曲的 ID，用于在切歌时发送给 JS
    private var lastMediaId: String? = null

    private val durationCache = mutableMapOf<String, Long>()

    val gson = Gson()

    override fun definition() = ModuleDefinition {
        Name("Orpheus")

        Events(
            "onPlaybackStateChanged",
            "onPlayerError",
            "onPositionUpdate",
            "onIsPlayingChanged",
            "onTrackFinished",
            "onTrackStarted"
        )

        OnCreate {
            val context = appContext.reactContext ?: return@OnCreate
            MediaItemStorer.initialize(context)
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
            mainHandler.removeCallbacks(progressSendEventRunnable)
            mainHandler.removeCallbacks(progressSaveRunnable)
            controllerFuture?.let { MediaController.releaseFuture(it) }
        }

        Constant("restorePlaybackPositionEnabled") {
            MediaItemStorer.isRestoreEnabled()
        }

        Function("setBilibiliCookie") { cookie: String ->
            OrpheusConfig.bilibiliCookie = cookie
        }

        Function("setRestorePlaybackPositionEnabled") { enabled: Boolean ->
            MediaItemStorer.setRestoreEnabled(enabled)
        }

        AsyncFunction("getPosition") {
            checkController()
            controller?.currentPosition?.toDouble()?.div(1000.0) ?: 0.0
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getDuration") {
            checkController()
            val d = controller?.duration ?: C.TIME_UNSET
            if (d == C.TIME_UNSET) 0.0 else d.toDouble() / 1000.0
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getBuffered") {
            checkController()
            controller?.bufferedPosition?.toDouble()?.div(1000.0) ?: 0.0
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getIsPlaying") {
            checkController()
            controller?.isPlaying ?: false
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getCurrentIndex") {
            checkController()
            controller?.currentMediaItemIndex ?: -1
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getCurrentTrack") {
            checkController()
            val player = controller ?: return@AsyncFunction null
            val currentItem = player.currentMediaItem ?: return@AsyncFunction null

            mediaItemToTrackRecord(currentItem)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getShuffleMode") {
            checkController()
            controller?.shuffleModeEnabled
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getIndexTrack") { index: Int ->
            checkController()
            val player = controller ?: return@AsyncFunction null

            if (index < 0 || index >= player.mediaItemCount) {
                return@AsyncFunction null
            }

            val item = player.getMediaItemAt(index)

            mediaItemToTrackRecord(item)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("play") {
            checkController()
            controller?.play()
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("pause") {
            checkController()
            controller?.pause()
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("clear") {
            checkController()
            controller?.clearMediaItems()
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("skipTo") { index: Int ->
            // 跳转到指定索引的开头
            checkController()
            controller?.seekTo(index, C.TIME_UNSET)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("skipToNext") {
            checkController()
            if (controller?.hasNextMediaItem() == true) {
                controller?.seekToNextMediaItem()
            }
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("skipToPrevious") {
            checkController()
            if (controller?.hasPreviousMediaItem() == true) {
                controller?.seekToPreviousMediaItem()
            }
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("seekTo") { seconds: Double ->
            checkController()
            val ms = (seconds * 1000).toLong()
            controller?.seekTo(ms)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("setRepeatMode") { mode: Int ->
            checkController()
            // mode: 0=OFF, 1=TRACK, 2=QUEUE
            val repeatMode = when (mode) {
                1 -> Player.REPEAT_MODE_ONE
                2 -> Player.REPEAT_MODE_ALL
                else -> Player.REPEAT_MODE_OFF
            }
            controller?.repeatMode = repeatMode
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("setShuffleMode") { enabled: Boolean ->
            checkController()
            controller?.shuffleModeEnabled = enabled
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getRepeatMode") {
            checkController()
            controller?.repeatMode
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("removeTrack") { index: Int ->
            checkController()
            if (index >= 0 && index < (controller?.mediaItemCount ?: 0)) {
                controller?.removeMediaItem(index)
            }
        }

        AsyncFunction("getQueue") {
            checkController()
            val player = controller ?: return@AsyncFunction emptyList<TrackRecord>()
            val count = player.mediaItemCount
            val queue = ArrayList<TrackRecord>(count)

            for (i in 0 until count) {
                val item = player.getMediaItemAt(i)
                queue.add(mediaItemToTrackRecord(item))
            }

            return@AsyncFunction queue
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("setSleepTimer") { durationMs: Long ->
            checkController()
            val command = SessionCommand(CustomCommands.CMD_START_TIMER, Bundle.EMPTY)
            val args = Bundle().apply {
                putLong(CustomCommands.KEY_DURATION, durationMs)
            }

            controller?.sendCustomCommand(command, args)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("getSleepTimerEndTime") {
            checkController()

            val command = SessionCommand(CustomCommands.CMD_GET_REMAINING, Bundle.EMPTY)
            val future = controller!!.sendCustomCommand(command, Bundle.EMPTY)

            val result = try {
                future.get()
            } catch (e: Exception) {
                throw CodedException("ERR_EXECUTION_FAILED", e.message, e)
            }

            if (result.resultCode == SessionResult.RESULT_SUCCESS) {
                val extras = result.extras
                if (extras.containsKey(CustomCommands.KEY_STOP_TIME)) {
                    val stopTime = extras.getLong(CustomCommands.KEY_STOP_TIME)
                    return@AsyncFunction stopTime
                }
            }

            return@AsyncFunction null
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("cancelSleepTimer") {
            checkController()
            val command = SessionCommand(CustomCommands.CMD_CANCEL_TIMER, Bundle.EMPTY)
            controller?.sendCustomCommand(command, Bundle.EMPTY)
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("addToEnd") { tracks: List<TrackRecord>, startFromId: String?, clearQueue: Boolean? ->
            checkController()
            val mediaItems = tracks.map { track ->
                track.toMediaItem(gson)
            }
            val player = controller ?: return@AsyncFunction
            if (clearQueue == true) {
                player.clearMediaItems()
            }
            val initialSize = player.mediaItemCount
            player.addMediaItems(mediaItems)

            if (!startFromId.isNullOrEmpty()) {
                val relativeIndex = tracks.indexOfFirst { it.id == startFromId }

                if (relativeIndex != -1) {
                    val targetIndex = initialSize + relativeIndex

                    player.seekTo(targetIndex, C.TIME_UNSET)
                    player.prepare()
                    player.play()

                    return@AsyncFunction
                }
            }

            if (player.playbackState == Player.STATE_IDLE) {
                player.prepare()
            }
        }.runOnQueue(Queues.MAIN)

        AsyncFunction("playNext") { track: TrackRecord ->
            checkController()
            val player = controller ?: return@AsyncFunction

            val mediaItem = track.toMediaItem(gson)
            val targetIndex = player.currentMediaItemIndex + 1

            var existingIndex = -1
            for (i in 0 until player.mediaItemCount) {
                if (player.getMediaItemAt(i).mediaId == track.id) {
                    existingIndex = i
                    break
                }
            }

            if (existingIndex != -1) {
                if (existingIndex == player.currentMediaItemIndex) {
                    return@AsyncFunction
                }
                val safeTargetIndex = targetIndex.coerceAtMost(player.mediaItemCount)

                player.moveMediaItem(existingIndex, safeTargetIndex)

            } else {
                val safeTargetIndex = targetIndex.coerceAtMost(player.mediaItemCount)

                player.addMediaItem(safeTargetIndex, mediaItem)
            }

            if (player.playbackState == Player.STATE_IDLE) {
                player.prepare()
            }
        }.runOnQueue(Queues.MAIN)
    }

    private fun setupListeners() {
        controller?.addListener(object : Player.Listener {

            /**
             * 核心：处理切歌、播放结束逻辑
             */
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val newId = mediaItem?.mediaId ?: ""
                Log.e("Orpheus", "onMediaItemTransition: $reason")

                sendEvent(
                    "onTrackStarted", mapOf(
                        "trackId" to newId,
                        "reason" to reason
                    )
                )

                lastMediaId = newId
                saveCurrentPosition()
            }

            override fun onTimelineChanged(timeline: Timeline, reason: Int) {
                val player = controller ?: return
                val currentItem = player.currentMediaItem ?: return
                val mediaId = currentItem.mediaId

                val duration = player.duration

                if (duration != C.TIME_UNSET && duration > 0) {
                    durationCache[mediaId] = duration
                }
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int
            ) {
                if (oldPosition.mediaItemIndex != newPosition.mediaItemIndex) {
                    val lastMediaItem =
                        controller?.getMediaItemAt(oldPosition.mediaItemIndex) ?: return

                    // onPositionDiscontinuity 会被连续调用两次，且两次调用参数相同，很奇怪的行为，所以采用这种方式过滤.没值就直接返回，不发事件。
                    val duration = durationCache.remove(lastMediaItem.mediaId) ?: return

                    sendEvent(
                        "onTrackFinished", mapOf(
                            "trackId" to lastMediaItem.mediaId,
                            "finalPosition" to oldPosition.positionMs / 1000.0,
                            "duration" to duration / 1000.0,
                        )
                    )
                }
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

    private val progressSendEventRunnable = object : Runnable {
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

    private val progressSaveRunnable = object : Runnable {
        override fun run() {
            saveCurrentPosition()
            mainHandler.postDelayed(this, 5000)
        }
    }

    private fun updateProgressRunnerState() {
        val player = controller
        // 如果正在播放且状态是 READY，则开始轮询
        if (player != null && player.isPlaying && player.playbackState == Player.STATE_READY) {
            mainHandler.removeCallbacks(progressSendEventRunnable)
            mainHandler.removeCallbacks(progressSaveRunnable)
            mainHandler.post(progressSaveRunnable)
            mainHandler.post(progressSendEventRunnable)
        } else {
            mainHandler.removeCallbacks(progressSendEventRunnable)
            mainHandler.removeCallbacks(progressSaveRunnable)
        }
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

    private fun saveCurrentPosition() {
        val player = controller ?: return
        if (player.playbackState != Player.STATE_IDLE) {
            MediaItemStorer.savePosition(
                player.currentMediaItemIndex,
                player.currentPosition
            )
        }
    }

    private fun checkController() {
        if (controller == null) {
            throw ControllerNotInitializedException()
        }
    }
}