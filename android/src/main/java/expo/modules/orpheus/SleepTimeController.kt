package expo.modules.orpheus

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.Player

class SleepTimerManager(private val player: Player) {
    private val handler = Handler(Looper.getMainLooper())

    private var targetTimeRaw: Long = 0
    private var isTimerActive = false

    private val checkRunnable = object : Runnable {
        override fun run() {
            if (!isTimerActive) return

            val now = SystemClock.elapsedRealtime()
            val timeLeft = targetTimeRaw - now

            if (timeLeft <= 0) {
                performStop()
            } else {
                handler.postDelayed(this, timeLeft)
            }
        }
    }

    /**
     * 开启定时器
     * @param duration 多少秒后停止
     */
    fun start(duration: Long) {
        if (duration <= 0) {
            cancel()
            return
        }

        targetTimeRaw = SystemClock.elapsedRealtime() + (duration.times(1000L))
        isTimerActive = true

        handler.removeCallbacks(checkRunnable)
        handler.postDelayed(checkRunnable, duration)
    }

    /**
     * 取消定时器
     */
    fun cancel() {
        isTimerActive = false
        handler.removeCallbacks(checkRunnable)
        targetTimeRaw = 0
    }

    /**
     * 获取剩余时间（单位：秒）
     */
    fun getRemainingTime(): Long {
        if (!isTimerActive) return -1L
        val remaining = (targetTimeRaw - SystemClock.elapsedRealtime()).div(1000L)
        return if (remaining > 0) remaining else 0
    }

    private fun performStop() {
        isTimerActive = false
        player.pause()
    }
}