import AVFoundation
import ExpoModulesCore
import MediaPlayer

class OrpheusPlayerManager: NSObject {
    static let shared = OrpheusPlayerManager()
    
    private var player: AVPlayer!
    private var queue: [Track] = []
    private var currentIndex: Int = -1
    
    var repeatMode: RepeatMode = .off
    var shuffleMode: Bool = false
    

    
    // Image Cache
    private var imageCache = NSCache<NSString, UIImage>()
    private var sleepTimer: Timer?
    private var sleepTimerEndTime: Date?
    
    // Original playlist for shuffle implementation
    private var originalQueue: [Track] = []
    
    // Events
    var onPlaybackStateChanged: ((PlaybackState) -> Void)?
    var onTrackStarted: ((String, TransitionReason) -> Void)?
    var onPositionUpdate: ((Double, Double, Double) -> Void)?
    var onIsPlayingChanged: ((Bool) -> Void)?
    var onPlayerError: ((String) -> Void)?
    
    override init() {
        super.init()
        player = AVPlayer()
        setupPlayerObservers()
        setupAudioSession()
        setupRemoteCommands()
        restoreState()
    }
    
    private var timeObserverToken: Any?
    
    private func setupPlayerObservers() {
        // Status observer
        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
        player.addObserver(self, forKeyPath: "currentItem.status", options: [.new], context: nil)
        
        // Periodic time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.notifyPositionUpdate()
        }
        
        // End of track observer
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus" {

            notifyPlaybackState()
        } else if keyPath == "currentItem.status" {
            let status = player.currentItem?.status ?? .unknown

            if status == .failed {
                let errorMsg = player.currentItem?.error?.localizedDescription ?? "unknown error"

                onPlayerError?(errorMsg)
                onPlaybackStateChanged?(.idle)
                onIsPlayingChanged?(false)
            }
        }
    }
    
    @objc private func playerDidFinishPlaying(note: NSNotification) {
        handleAutoAdvance()
    }
    
    private func handleAutoAdvance() {
        if repeatMode == .track {
            player.seek(to: .zero)
            player.play()
            return
        }
        
        skipToNext(reason: .auto)
    }
    
    // MARK: - Queue Management
    
    // Current effective queue (mapped)
    func getQueue() -> [Track] {
        if let indices = shuffleIndices {
            return indices.compactMap { index in
                guard index >= 0 && index < backingQueue.count else { return nil }
                return backingQueue[index]
            }
        }
        return backingQueue
    }
    
    func getCurrentTrack() -> Track? {
        guard currentIndex >= 0 else { return nil }
        
        let actualIndex = getActualIndex(from: currentIndex)
        guard actualIndex >= 0 && actualIndex < backingQueue.count else { return nil }
        
        return backingQueue[actualIndex]
    }
    
    func getTrack(at index: Int) -> Track? {
        // index is playback index
        guard index >= 0 else { return nil }
        
        if let indices = shuffleIndices {
             guard index < indices.count else { return nil }
             let actualIndex = indices[index]
             guard actualIndex >= 0 && actualIndex < backingQueue.count else { return nil }
             return backingQueue[actualIndex]
        }
        
        guard index < backingQueue.count else { return nil }
        return backingQueue[index]
    }
    
    // Helper to get backing index from playback index
    private func getActualIndex(from playbackIndex: Int) -> Int {
        if let indices = shuffleIndices {
            if playbackIndex >= 0 && playbackIndex < indices.count {
                return indices[playbackIndex]
            }
        } else {
            return playbackIndex
        }
        return -1
    }
    
    func getCurrentIndex() -> Int {
        return currentIndex
    }
    
    func setQueue(_ tracks: [Track], startIndex: Int) {
        // Reset state
        backingQueue = tracks
        
        if shuffleMode {
            shuffleIndices = Array(0..<tracks.count).shuffled()
            // Find where startItem ended up in shuffle
            // But wait, startIndex is usually index in the NEW un-shuffled queue?
            // Actually usually setQueue passes data and where to start.
            // If shuffle is ON, we might want to start at that specific TRACK, effectively moving it to 0 or finding it?
            // Standard behavior: Play that track, and mapped queue is shuffled but usually start track is first?
            // Or just find it.
            
            // Let's match typical "Shuffle Play" behavior:
            // If startIndex is provided, we probably want to play THAT track.
            // So we find that track's original index (which is startIndex), and find it in shuffleIndices.
            // OR we swap it to 0.
            
            // For now: Just shuffle and find new index of that track.
            if let newIndex = shuffleIndices?.firstIndex(of: startIndex) {
                currentIndex = newIndex
            } else {
                // Fallback (shouldn't happen if indices are correct)
                currentIndex = 0 
            }
            
            // Actually, many players enforce that start track is first in shuffled queue.
            // Let's do that for better UX.
            if let currentSlot = shuffleIndices?.firstIndex(of: startIndex) {
                shuffleIndices?.swapAt(0, currentSlot)
                currentIndex = 0
            }
            
        } else {
            shuffleIndices = nil
            currentIndex = startIndex
        }
        
        let count = getQueueCount()
        if currentIndex >= 0 && currentIndex < count {
            playTrack(at: currentIndex, reason: .playlistChanged)
        }
        
        saveState()
    }
    
    private func getQueueCount() -> Int {
        return backingQueue.count // shuffled or not, count is same
    }
    
    func removeTrack(at index: Int) {
        // Index is playback index
        guard index >= 0 else { return }
        
        var backingIndexToRemove = -1
        
        if var indices = shuffleIndices {
            guard index < indices.count else { return }
            backingIndexToRemove = indices[index]
            
            // Remove from shuffle indices
            indices.remove(at: index)
            
            // Adjust indices that are greater than backingIndexToRemove
            for i in 0..<indices.count {
                if indices[i] > backingIndexToRemove {
                    indices[i] -= 1
                }
            }
            shuffleIndices = indices
        } else {
            guard index < backingQueue.count else { return }
            backingIndexToRemove = index
        }
        
        // Remove from backing queue
        guard backingIndexToRemove >= 0 && backingIndexToRemove < backingQueue.count else { return }
        let removedTrack = backingQueue.remove(at: backingIndexToRemove)
        
        // Handle playback state
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Removed current track
             if getQueueCount() == 0 {
                // Stopped
                player.pause()
                player.replaceCurrentItem(with: nil)
                currentIndex = -1
                onPlaybackStateChanged?(.ended)
                onIsPlayingChanged?(false) 
                notifyPositionUpdate() 
            } else {
                if currentIndex >= getQueueCount() {
                    if repeatMode == .queue {
                        currentIndex = 0
                        playTrack(at: currentIndex, reason: .playlistChanged)
                    } else {
                        // Stop
                        currentIndex = 0
                        player.pause()
                        player.replaceCurrentItem(with: nil)
                        onPlaybackStateChanged?(.idle)
                        onIsPlayingChanged?(false)
                    }
                } else {
                     playTrack(at: currentIndex, reason: .playlistChanged)
                }
            }
        }
        
        saveState()
    }
    
    func clearQueue() {
        backingQueue.removeAll()
        shuffleIndices = nil
        currentIndex = -1
        player.pause()
        player.replaceCurrentItem(with: nil)
        onPlaybackStateChanged?(.idle)
        onIsPlayingChanged?(false)
        updateNowPlayingInfo()
        saveState()
    }
    
    func addToNext(track: Track) {
        if backingQueue.isEmpty {
            addToEnd(tracks: [track], startFromId: nil, clearQueue: false)
            return
        }
        
        let insertPlaybackIndex = currentIndex + 1
        
        // Append to backing queue
        backingQueue.append(track)
        let newBackingIndex = backingQueue.count - 1
        
        if var indices = shuffleIndices {
            // Insert at next playback position
            if insertPlaybackIndex <= indices.count {
                indices.insert(newBackingIndex, at: insertPlaybackIndex)
            } else {
                indices.append(newBackingIndex)
            }
            shuffleIndices = indices
        }
        // If not shuffled, it's just appended to backing queue which is next only if we are at end.
        // Wait, "play next" means insert after current playing item.
        else {
             if insertPlaybackIndex <= backingQueue.count - 1 { // -1 because we just appended
                  // Move the newly appended item to correct position
                  // backingQueue.remove(at: newBackingIndex) -> removed
                  // backingQueue.insert(track, at: insertPlaybackIndex)
                  // Efficient way:
                  backingQueue.insert(track, at: insertPlaybackIndex)
                  backingQueue.removeLast() // Remove the one we appended first
             }
             // Actually, simplest is just insert directly.
             backingQueue.insert(track, at: insertPlaybackIndex)
             // But I already appended above? Remove that logic.
             // Just:
             // backingQueue.insert(track, at: insertPlaybackIndex)
             // But wait, my code block above did `backingQueue.append`.
        }
    }
    
    // ... (addToEnd implementation) ...
    
    func addToEnd(tracks: [Track], startFromId: String?, clearQueue: Bool) {
        if clearQueue {
            setQueue(tracks, startIndex: 0)
            if let startId = startFromId, let index = tracks.firstIndex(where: { $0.id == startId }) {
                setQueue(tracks, startIndex: index)
            }
        } else {
            // Append to backing
            let startBackingIndex = backingQueue.count
            backingQueue.append(contentsOf: tracks)
            
            if var indices = shuffleIndices {
                // Add new indices to end of shuffle indices
                let newIndices = (startBackingIndex..<(startBackingIndex + tracks.count))
                // Shuffle them? Or just append?
                // Usually "Play Next" adds to next, "Add to Queue" adds to end.
                // If shuffled, "End" of playback queue is random? Or truly end?
                // Usually it just appends to the playback order too.
                indices.append(contentsOf: newIndices)
                shuffleIndices = indices
            }
        }
        
        if !clearQueue, let startId = startFromId {
            // Find in playback order 
            // We need to look through playback indices if shuffled
            // Or just check logic of setQueue
             if let backingIndex = backingQueue.firstIndex(where: { $0.id == startId }) {
                 // Find playback index for this backing index
                 if let indices = shuffleIndices {
                     if let playbackIndex = indices.firstIndex(of: backingIndex) {
                          playTrack(at: playbackIndex, reason: .playlistChanged)
                     }
                 } else {
                     playTrack(at: backingIndex, reason: .playlistChanged)
                 }
            }
        }
        
        saveState()
    }
    
    func setExecuteShuffleMode(_ enabled: Bool) {
        guard shuffleMode != enabled else { return }
        shuffleMode = enabled
        
        if enabled {
            // Turning shuffle ON
            // Create shuffled indices
            // Keep current track at index 0? or keep strict mapping?
            // Usually we want current track to stay current track.
            
            var newIndices = Array(0..<backingQueue.count).shuffled()
            
            // Move current playing track to 0 in shuffle
            if currentIndex >= 0 { // currentIndex is BACKING index here because shuffle WAS off
                 let currentBackingIndex = currentIndex
                 
                 if let slot = newIndices.firstIndex(of: currentBackingIndex) {
                     newIndices.swapAt(0, slot)
                     currentIndex = 0 // Now it's at playback index 0
                 }
            } else {
                 currentIndex = -1
            }
            shuffleIndices = newIndices
            
        } else {
            // Turning shuffle OFF
            // Map playback index BACK to backing index
            if let indices = shuffleIndices, currentIndex >= 0 && currentIndex < indices.count {
                let currentBackingIndex = indices[currentIndex]
                currentIndex = currentBackingIndex // Restore to backing index
            }
            shuffleIndices = nil
        }
        saveState()
    }
    
    func setExecuteRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        saveState()
    }
    
    // Removed old shuffleQueue method as it's replaced by logic above

    
    // MARK: - Playback Control
    
    func play() {
        if player.currentItem == nil && currentIndex >= 0 {

             playTrack(at: currentIndex, reason: .auto)
             return
        }
        if player.status == .failed || player.currentItem?.status == .failed {

             playTrack(at: currentIndex, reason: .auto)
             return
        }
        player.play()
    }
    
    func pause() {
        player.pause()
    }
    
    func playNext() {
        skipToNext(reason: .seek)
    }
    
    func skipToNext(reason: TransitionReason) {
        let count = getQueueCount()
        if count == 0 { return }
        
        // If Repeat One, usually 'Next' button forces next track anyway, ignoring Repeat One.
        // Auto-advance respects Repeat One.
        // `skipToNext` is usually manual action. `handleAutoAdvance` calls this with reason=.auto
        
        var nextIndex = currentIndex + 1
        
        // Handle Cycle
        if nextIndex >= count {
            if repeatMode == .queue || repeatMode == .track { // Repeat Track usually circles in playlist too if manually skipped?
                 nextIndex = 0
            } else {
                // End of queue
                onPlaybackStateChanged?(.ended)
                return
            }
        }
        
        playTrack(at: nextIndex, reason: reason)
    }
    
    func skipToPrevious() {
        // If playing > 3 seconds, restart current track? Standard iOS behavior.
        if player.currentTime().seconds > 3.0 {
            player.seek(to: CMTime.zero)
            return
        }
        
        var prevIndex = currentIndex - 1
        if prevIndex < 0 {
             if repeatMode == .queue || repeatMode == .track {
                 let count = getQueueCount()
                 prevIndex = count - 1
             } else {
                 player.seek(to: CMTime.zero)
                 return
             }
        }
        
        playTrack(at: prevIndex, reason: .seek)
    }
    
    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        player.seek(to: time)
    }
    
    // MARK: - Track Loading
    
    private func playTrack(at index: Int, reason: TransitionReason, startPosition: Double? = nil) {
        guard let track = getTrack(at: index) else {
            return
        }
        
        // Optimistic update
        self.currentIndex = index


        onTrackStarted?(track.id, reason)
        saveState()
        
        let urlString = track.url

        
        // Check for local download first
        if let localUrl = OrpheusDownloadManager.shared.getDownloadedFileUrl(id: track.id) {

             // Use local file
             loadAvPlayerItem(url: localUrl.absoluteString, headers: nil, startPosition: startPosition)
             return
        }
        
        if urlString.starts(with: "orpheus://bilibili") {

            resolveAndPlayBilibili(url: urlString, startPosition: startPosition)
        } else {

            loadAvPlayerItem(url: urlString, headers: nil, startPosition: startPosition)
        }
    }
    
    private func resolveAndPlayBilibili(url: String, startPosition: Double? = nil) {
        guard let uri = URL(string: url),
              let components = URLComponents(url: uri, resolvingAgainstBaseURL: false) else {

            onPlayerError?("Invalid Bilibili URL")
            onPlaybackStateChanged?(.idle)
            return
        }
        
        let bvid = components.queryItems?.first(where: { $0.name == "bvid" })?.value
        let cid = components.queryItems?.first(where: { $0.name == "cid" })?.value
        
        guard let bvid = bvid else {

            onPlayerError?("Missing bvid in URL")
            onPlaybackStateChanged?(.idle)
            return
        }
        
        if let cid = cid {
            fetchBilibiliPlayUrl(bvid: bvid, cid: cid, startPosition: startPosition)
        } else {

            BilibiliApi.shared.getPageList(bvid: bvid) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let cidInt):

                        self?.fetchBilibiliPlayUrl(bvid: bvid, cid: String(cidInt), startPosition: startPosition)
                    case .failure(let error):

                        self?.onPlayerError?(error.localizedDescription)
                        self?.onPlaybackStateChanged?(.idle)
                    }
                }
            }
        }
    }
    
    private func fetchBilibiliPlayUrl(bvid: String, cid: String, startPosition: Double? = nil) {

        
        BilibiliApi.shared.getPlayUrl(bvid: bvid, cid: cid) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let realUrl):

                    // Bilibili requires Referer header
                    let headers: [String: String] = [
                        "Referer": "https://www.bilibili.com/",
                        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                    ]
                    self?.loadAvPlayerItem(url: realUrl, headers: headers, startPosition: startPosition)
                case .failure(let error):

                    self?.onPlayerError?(error.localizedDescription)
                    // Reset state so UI doesn't stick in loading
                    self?.onPlaybackStateChanged?(.idle)
                }
            }
        }
    }
    
    private func loadAvPlayerItem(url: String, headers: [String: String]?, startPosition: Double? = nil) {
        guard let nsUrl = URL(string: url) else {

            return
        }
        

        
        let asset: AVURLAsset
        if let headers = headers {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            asset = AVURLAsset(url: nsUrl, options: options)
        } else {
            asset = AVURLAsset(url: nsUrl)
        }
        
        let item = AVPlayerItem(asset: asset)
        

        player.replaceCurrentItem(with: item)
        if let startPos = startPosition, startPos > 0 {
             let time = CMTime(seconds: startPos, preferredTimescale: 1000)
             player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        

    }
    
    // MARK: - Notification
    
    private func notifyPositionUpdate() {
        let currentTime = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        let buffered = player.currentItem?.loadedTimeRanges.last?.timeRangeValue.end.seconds ?? 0
        
        onPositionUpdate?(currentTime, duration, buffered)
        
        // Update lock screen progress
        // Only update occasionally or on state change to avoid spamming? 
        // Actually MPNowPlayingInfoCenter handles 'elapsedPlaybackTime' so we don't need to push every split second 
        // unless status changes or seek happens.
        // However, we should update it when rate changes.
    }
    
    private func notifyPlaybackState() {
        var state: PlaybackState = .idle
        switch player.timeControlStatus {
        case .paused:
            state = .ready

        case .waitingToPlayAtSpecifiedRate:
            state = .buffering

        case .playing:
            state = .ready

        @unknown default:
            state = .idle

        }
        
        onPlaybackStateChanged?(state)
        onIsPlayingChanged?(isPlaying())
        
        if state == .ready || state == .idle {
             savePositionState()
        }
        
        updateNowPlayingInfo()
    }
    
    // MARK: - System Integration
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            
            // Interruption observer
            NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: session)
        } catch {

        }
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .began {
            // Audio interrupted (phone call, etc.), pause player
            // Player usually pauses itself? but we should update UI state?
            // AVPlayer pauses automatically on interruption usually if not configured otherwise.
            // But we might want to manually pause to ensure state is synced.
             pause()
        } else if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        }
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            if self.isPlaying() {
                self.pause()
            } else {
                self.play()
            }
            return .success
        }
        
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.pause()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            self?.playNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            self?.skipToPrevious()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let track = getCurrentTrack() else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        // Ensure audio session is active for lock screen controls to appear
        // Sometimes it gets deactivated on pause or background switch
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? "Unknown Title",
            MPMediaItemPropertyArtist: track.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: getQueueCount()
        ]
        
        if let duration = track.duration {
             info[MPMediaItemPropertyPlaybackDuration] = duration
        } else if let playerDuration = player.currentItem?.duration.seconds, !playerDuration.isNaN {
             info[MPMediaItemPropertyPlaybackDuration] = playerDuration
        }
        
        // Artwork
        if let artworkUrlStr = track.artwork, let artworkUrl = URL(string: artworkUrlStr) {
            downloadImage(url: artworkUrl) { image in
                guard let image = image else { return }
                
                // Re-fetch because concurrent updates might have happened
                if var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    // Check if we are still on the same track roughly (title check or id check if we stored it)
                    // Simple check: Title matches
                    if currentInfo[MPMediaItemPropertyTitle] as? String == track.title {
                         let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                         currentInfo[MPMediaItemPropertyArtwork] = artwork
                         MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                    }
                } else {
                    // If info was cleared but we just got image, maybe we should set it again?
                    // Safe to just update info variable and set it?
                    // We need to carry over the other fields.
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // Simple image downloader helper
    private func downloadImage(url: URL, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    func skipTo(index: Int) {
        guard index >= 0 && index < getQueueCount() else { return }
        playTrack(at: index, reason: .seek)
    }
    
    // MARK: - Playback Attributes
    
    func setPlaybackSpeed(_ speed: Float) {
        player.rate = speed
    }
    
    func getPlaybackSpeed() -> Float {
        return player.rate
    }
    
    // MARK: - Getters
    
    func getPosition() -> Double {
        return player.currentTime().seconds
    }
    
    func getBufferedPosition() -> Double {
        return player.currentItem?.loadedTimeRanges.last?.timeRangeValue.end.seconds ?? 0.0
    }
    
    func getDuration() -> Double {
        return player.currentItem?.duration.seconds ?? 0.0
    }
    
    func isPlaying() -> Bool {
        return player.rate > 0 && player.error == nil
    }
    
    // MARK: - Sleep Timer
    
    func setSleepTimer(durationMs: Double) {
        cancelSleepTimer()
        
        let interval = durationMs / 1000.0
        sleepTimerEndTime = Date().addingTimeInterval(interval)
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.pause()
            self?.cancelSleepTimer()
        }
    }
    
    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndTime = nil
    }
    
    func getSleepTimerEndTime() -> Double? {
        guard let endTime = sleepTimerEndTime else { return nil }
        return endTime.timeIntervalSince1970 * 1000.0
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        GeneralStorage.shared.saveQueue(backingQueue)
        
        GeneralStorage.shared.savePosition(
            index: currentIndex,
            positionSec: player.currentTime().seconds
        )
        
        GeneralStorage.shared.saveRepeatMode(repeatMode.rawValue)
        GeneralStorage.shared.saveShuffleMode(shuffleMode)
    }
    
    private func savePositionState() {
        let seconds = player.currentTime().seconds
        GeneralStorage.shared.savePosition(index: currentIndex, positionSec: seconds)
    }

    private func restoreState() {
        // Restore Modes
        if let mode = RepeatMode(rawValue: GeneralStorage.shared.getSavedRepeatMode()) {
            repeatMode = mode
        }
        shuffleMode = GeneralStorage.shared.getSavedShuffleMode()
        
        // Restore Queue
        let restoredQueue = GeneralStorage.shared.getSavedQueue()
        if !restoredQueue.isEmpty {
            backingQueue = restoredQueue
            
            if shuffleMode {
                 shuffleIndices = Array(0..<backingQueue.count).shuffled()
            } else {
                 shuffleIndices = nil
            }
        }
        
        // Restore Index and Position
        let savedIndex = GeneralStorage.shared.getSavedIndex()
        var savedPosition = 0.0
        if GeneralStorage.shared.isRestoreEnabled {
            savedPosition = GeneralStorage.shared.getSavedPosition()
        }
        
        if !queue.isEmpty {
            self.currentIndex = savedIndex
            // Don't auto play, just prepare
            if savedIndex >= 0 && savedIndex < queue.count {
                // Seek to position, but don't play yet?
                // We create a player item but don't play
                let track = queue[savedIndex]
                
                // We need to load the item but PAUSED
                // Re-use logic but avoid .play()
                // Or just set currentIndex and wait for user to press play?
                // User expects "Resume" capability.
                // We can load the item partially?
                // Let's try to just set state so UI reflects it.
                // Sending 'onTrackStarted' might be needed for UI to update properly.
                // We won't actually load the AVPlayerItem until user hits play to save resources/bandwidth on startup?
                // OR we load it paused.
                
                // Let's load it paused.
                // Cannot call playTrack -> it plays.
                // We manually set up.
                
                // Auto Play Logic
                if GeneralStorage.shared.isAutoplayOnStartEnabled {

                    playTrack(at: savedIndex, reason: .playlistChanged, startPosition: savedPosition > 0 ? savedPosition : nil)
                } else {
                    // Start Paused

                     onTrackStarted?(track.id, .playlistChanged)
                     
                     // If we want to be ready to play at position:

                     // Simple approach: restore indices, let UI show it. 
                     // Updating position might be tricky if player is empty.
                     // We can emit a position update manually?
                     onPositionUpdate?(savedPosition, track.duration ?? 0, 0)
                }
            }
        }
    }
}
