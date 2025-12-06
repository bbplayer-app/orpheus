package expo.modules.orpheus

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

@UnstableApi
object DownloadCache {
    private var cache: SimpleCache? = null

    @UnstableApi
    fun get(context: Context): SimpleCache {
        if (cache == null) {
            val cacheDir = File(context.cacheDir, "media_cache")
            val evictor = LeastRecentlyUsedCacheEvictor(256 * 1024 * 1024)
            val databaseProvider = StandaloneDatabaseProvider(context)

            cache = SimpleCache(cacheDir, evictor, databaseProvider)
        }
        return cache!!
    }
}