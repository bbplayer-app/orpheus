import ExpoModulesCore

public class ExpoOrpheusModule: Module {
    
    private func setupEventListeners() {
        let manager = OrpheusPlayerManager.shared
        
        manager.onPlaybackStateChanged = { [weak self] state in
            self?.sendEvent("onPlaybackStateChanged", ["state": state.rawValue])
        }
        
        manager.onTrackStarted = { [weak self] trackId, reason in
            self?.sendEvent("onTrackStarted", ["trackId": trackId, "reason": reason.rawValue])
        }
        
        manager.onPositionUpdate = { [weak self] position, duration, buffered in
            self?.sendEvent("onPositionUpdate", [
                "position": position,
                "duration": duration,
                "buffered": buffered
            ])
        }
        
        OrpheusDownloadManager.shared.onDownloadUpdated = { [weak self] task in
            self?.sendEvent("onDownloadUpdated", [
                "id": task.id,
                "state": task.state.rawValue,
                "percentDownloaded": task.percentDownloaded,
                "bytesDownloaded": task.bytesDownloaded,
                "contentLength": task.contentLength
            ])
        }
        
        manager.onPlayerError = { [weak self] errorMsg in
            self?.sendEvent("onPlayerError", ["error": errorMsg])
        }
        
        manager.onIsPlayingChanged = { [weak self] isPlaying in
            self?.sendEvent("onIsPlayingChanged", ["status": isPlaying])
        }
    }
    
    public func definition() -> ModuleDefinition {
        Name("Orpheus")
        
        // Events
        Events(
            "onPlaybackStateChanged",
            "onTrackStarted",
            "onTrackFinished",
            "onPlayerError",
            "onPositionUpdate",
            "onIsPlayingChanged",
            "onDownloadUpdated",
            "onPlaybackSpeedChanged"
        )
        
        OnCreate {
            self.setupEventListeners()
        }

        // MARK: - Preferences
        
        Property("restorePlaybackPositionEnabled")
            .get { return UserDefaults.standard.bool(forKey: "restorePlaybackPositionEnabled") }
            .set { (newValue: Bool) in
                UserDefaults.standard.set(newValue, forKey: "restorePlaybackPositionEnabled")
            }
        
        Property("loudnessNormalizationEnabled")
            .get { return UserDefaults.standard.bool(forKey: "loudnessNormalizationEnabled") }
            .set { (newValue: Bool) in
                UserDefaults.standard.set(newValue, forKey: "loudnessNormalizationEnabled")
            }
        
        Property("autoplayOnStartEnabled")
            .get { return UserDefaults.standard.bool(forKey: "autoplayOnStartEnabled") }
            .set { (newValue: Bool) in
                UserDefaults.standard.set(newValue, forKey: "autoplayOnStartEnabled")
            }
        
    // MARK: - Getters
    
    AsyncFunction("getPosition") { () -> Double in
        return OrpheusPlayerManager.shared.getPosition()
    }
    
    AsyncFunction("getDuration") { () -> Double in
        return OrpheusPlayerManager.shared.getDuration()
    }
    
    AsyncFunction("getBuffered") { () -> Double in
        return OrpheusPlayerManager.shared.getBufferedPosition()
    }
    
    AsyncFunction("getIsPlaying") { () -> Bool in
        return OrpheusPlayerManager.shared.isPlaying()
    }
    
    AsyncFunction("getCurrentIndex") { () -> Int in
        return OrpheusPlayerManager.shared.getCurrentIndex()
    }
    
    AsyncFunction("getCurrentTrack") { () -> Track? in
        return OrpheusPlayerManager.shared.getCurrentTrack()
    }
    
    AsyncFunction("getQueue") { () -> [Track] in
        return OrpheusPlayerManager.shared.getQueue()
    }
    
    AsyncFunction("getIndexTrack") { (index: Int) -> Track? in
        return OrpheusPlayerManager.shared.getTrack(at: index)
    }
    
    AsyncFunction("getPlaybackSpeed") { () -> Double in
        return Double(OrpheusPlayerManager.shared.getPlaybackSpeed())
    }
    
    AsyncFunction("getRepeatMode") { () -> Int in
        return OrpheusPlayerManager.shared.repeatMode.rawValue
    }
    
    AsyncFunction("getShuffleMode") { () -> Bool in
        return OrpheusPlayerManager.shared.shuffleMode
    }
    
    // MARK: - Controls
    
    AsyncFunction("play") {
        OrpheusPlayerManager.shared.play()
    }

    AsyncFunction("pause") {
        OrpheusPlayerManager.shared.pause()
    }
    
    AsyncFunction("skipToNext") {
        OrpheusPlayerManager.shared.playNext()
    }
    
    AsyncFunction("skipToPrevious") {
        OrpheusPlayerManager.shared.skipToPrevious()
    }
    
    AsyncFunction("seekTo") { (seconds: Double) in
        OrpheusPlayerManager.shared.seek(to: seconds)
    }
    
    AsyncFunction("skipTo") { (index: Int) in
        OrpheusPlayerManager.shared.skipTo(index: index)
    }
    
    AsyncFunction("addToEnd") { (tracks: [Track], startFromId: String?, clearQueue: Bool) in
        OrpheusPlayerManager.shared.addToEnd(tracks: tracks, startFromId: startFromId, clearQueue: clearQueue)
    }
    
    AsyncFunction("playNext") { (track: Track) in
        OrpheusPlayerManager.shared.addToNext(track: track)
    }
    
    AsyncFunction("removeTrack") { (index: Int) in
        OrpheusPlayerManager.shared.removeTrack(at: index)
    }
    
    AsyncFunction("clear") {
         OrpheusPlayerManager.shared.clearQueue()
    }
    
    AsyncFunction("setPlaybackSpeed") { (speed: Double) in
        OrpheusPlayerManager.shared.setPlaybackSpeed(Float(speed))
    }
    
    Function("setBilibiliCookie") { (cookie: String) in
        BilibiliApi.shared.setCookie(cookie)
    }
    
    Function("setShuffleMode") { (enabled: Bool) in
        OrpheusPlayerManager.shared.setExecuteShuffleMode(enabled)
    }
    
    Function("setRepeatMode") { (mode: Int) in
        if let repeatMode = RepeatMode(rawValue: mode) {
            OrpheusPlayerManager.shared.setExecuteRepeatMode(repeatMode)
        }
    }
    
    Function("setSleepTimer") { (durationMs: Double) in
        OrpheusPlayerManager.shared.setSleepTimer(durationMs: durationMs)
    }
    
    Function("getSleepTimerEndTime") { () -> Double? in
        return OrpheusPlayerManager.shared.getSleepTimerEndTime()
    }
    
    Function("cancelSleepTimer") {
        OrpheusPlayerManager.shared.cancelSleepTimer()
    }
    
    // MARK: - Downloads
    
    Function("downloadTrack") { (track: Track) in
        OrpheusDownloadManager.shared.downloadTrack(track: track)
    }
    
    Function("multiDownload") { (tracks: [Track]) in
        OrpheusDownloadManager.shared.multiDownload(tracks: tracks)
    }
    
    Function("removeDownload") { (id: String) in
        OrpheusDownloadManager.shared.removeDownload(id: id)
    }
    
    Function("removeAllDownloads") {
        OrpheusDownloadManager.shared.removeAllDownloads()
    }
    
    Function("getDownloads") { () -> [DownloadTask] in
        return OrpheusDownloadManager.shared.getDownloads()
    }
    
    Function("getDownloadStatusByIds") { (ids: [String]) -> [String: Int] in
        return OrpheusDownloadManager.shared.getDownloadStatusByIds(ids: ids)
    }
    
    Function("clearUncompletedDownloadTasks") {
        OrpheusDownloadManager.shared.clearUncompletedTasks()
    }
    
    Function("getUncompletedDownloadTasks") { () -> [DownloadTask] in
         return OrpheusDownloadManager.shared.getUncompletedTasks()
    }
  }
}
