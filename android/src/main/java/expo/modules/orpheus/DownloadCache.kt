package expo.modules.orpheus

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

@UnstableApi
object DownloadCache {
    private var stableCache: SimpleCache? = null

    @Synchronized
    fun getStableCache(context: Context): SimpleCache {
        if (stableCache == null) {
            val cacheDir = File(context.filesDir, "media_download")
            val evictor = NoOpCacheEvictor()
            val databaseProvider = StandaloneDatabaseProvider(context)
            stableCache = SimpleCache(cacheDir, evictor, databaseProvider)
        }
        return stableCache!!
    }
}