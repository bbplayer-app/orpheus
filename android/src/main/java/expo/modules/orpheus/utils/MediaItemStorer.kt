package expo.modules.orpheus.utils

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.tencent.mmkv.MMKV
import expo.modules.orpheus.models.TrackRecord

@OptIn(UnstableApi::class)
object MediaItemStorer {
    private var kv: MMKV? = null
    private val gson = Gson()
    private const val KEY_RESTORE_POSITION_ENABLED = "config_restore_position_enabled"
    private const val KEY_SAVED_QUEUE = "saved_queue_json_list"
    private const val KEY_SAVED_INDEX = "saved_index"
    private const val KEY_SAVED_POSITION = "saved_position"


    fun initialize(context: Context) {
        if (kv == null) {
            MMKV.initialize(context)
            kv = MMKV.mmkvWithID("player_queue_store")
        }
    }

    private val safeKv: MMKV
        get() = kv ?: throw IllegalStateException("MediaItemStorer not initialized")

    fun setRestoreEnabled(enabled: Boolean) {
        try {
            safeKv.encode(KEY_RESTORE_POSITION_ENABLED, enabled)
        } catch (e: Exception) {
            Log.e("MediaItemStorer", "Failed to set restore position enabled", e)
        }
    }

    fun isRestoreEnabled(): Boolean {
        return safeKv.decodeBool(KEY_RESTORE_POSITION_ENABLED, false)
    }

    @OptIn(UnstableApi::class)
    fun saveQueue(mediaItems: List<MediaItem>) {
        try {
            val jsonList = mediaItems.mapNotNull { item ->
                item.mediaMetadata.extras?.getString("track_json")
            }

            val jsonListString = gson.toJson(jsonList)
            safeKv.encode(KEY_SAVED_QUEUE, jsonListString)

        } catch (e: Exception) {
            Log.e("MediaItemStorer", "Failed to save queue", e)
        }
    }

    fun restoreQueue(): List<MediaItem> {
        return try {
            val jsonListString = kv?.decodeString(KEY_SAVED_QUEUE)

            if (jsonListString.isNullOrEmpty()) return emptyList()

            val listType = object : TypeToken<List<String>>() {}.type
            val trackJsonList: List<String> = gson.fromJson(jsonListString, listType)

            trackJsonList.mapNotNull { trackJson ->
                try {
                    val track = gson.fromJson(trackJson, TrackRecord::class.java)

                    track.toMediaItem(gson)

                } catch (e: Exception) {
                    Log.e("MediaItemStorer", "Failed to parse track json: $trackJson", e)
                    null
                }
            }
        } catch (e: Exception) {
            Log.e("MediaItemStorer", "Failed to restore queue", e)
            emptyList()
        }
    }

    fun savePosition(index: Int, position: Long) {
        safeKv.encode(KEY_SAVED_INDEX, index)
        safeKv.encode(KEY_SAVED_POSITION, position)
    }

    fun getSavedIndex() = kv?.decodeInt(KEY_SAVED_INDEX, 0) ?: 0
    fun getSavedPosition() = kv?.decodeLong(KEY_SAVED_POSITION, 0L) ?: 0L
}