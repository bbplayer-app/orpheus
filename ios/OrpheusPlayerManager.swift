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
    
    // Add conformance for encoding/decoding
    // Record in Expo might act as Codable but let's be explicit if needed or rely on standard Codable for struct
    // Since Track is struct, we need it to verify conformity.
    // Expo's Record: "A Swift struct that implements this protocol can be converted to/from a JS object."
    // It implements Codable.
    
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
            print("[OrpheusPlayer] timeControlStatus changed: \(player.timeControlStatus.rawValue)")
            notifyPlaybackState()
        } else if keyPath == "currentItem.status" {
            let status = player.currentItem?.status ?? .unknown
            print("[OrpheusPlayer] currentItem.status changed: \(status.rawValue)")
            if status == .failed {
                let errorMsg = player.currentItem?.error?.localizedDescription ?? "unknown error"
                print("[OrpheusPlayer] currentItem error: \(errorMsg)")
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
    
    func getQueue() -> [Track] {
        return queue
    }
    
    func getCurrentTrack() -> Track? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    func getTrack(at index: Int) -> Track? {
        guard index >= 0 && index < queue.count else { return nil }
        return queue[index]
    }
    
    func getCurrentIndex() -> Int {
        return currentIndex
    }
    
    func setQueue(_ tracks: [Track], startIndex: Int) {
        // Reset state
        originalQueue = tracks
        queue = tracks
        
        if shuffleMode {
            shuffleQueue(keepCurrentIndex: startIndex)
        } else {
            currentIndex = startIndex
        }
        
        if currentIndex >= 0 && currentIndex < queue.count {
            playTrack(at: currentIndex, reason: .playlistChanged)
        }
        
        saveState()
    }
    
    func removeTrack(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        let removedTrack = queue.remove(at: index)
        originalQueue.removeAll { $0.id == removedTrack.id } // Also remove from original
        
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Removing currently playing track
            if queue.isEmpty {
                // Stopped
                player.pause()
                player.replaceCurrentItem(with: nil)
                currentIndex = -1
                onPlaybackStateChanged?(.ended)
                onIsPlayingChanged?(false) // Force update
                notifyPositionUpdate() 
            } else {
                // Play next valid or current (which is now new track at this index)
                // If we removed last item, currentIndex is now out of bounds
                if currentIndex >= queue.count {
                    currentIndex = 0 // loop or stop? Android keeps playing? 
                    // Usually if you remove current, it skips to next.
                    // If last was removed, maybe loop to 0?
                }
                playTrack(at: currentIndex, reason: .playlistChanged) // reason?
            }
        }
    }
    
    func clearQueue() {
        queue.removeAll()
        originalQueue.removeAll()
        currentIndex = -1
        player.pause()
        player.replaceCurrentItem(with: nil)
        onPlaybackStateChanged?(.idle)
        onIsPlayingChanged?(false)
        updateNowPlayingInfo()
    }
    
    func addToNext(track: Track) {
        if queue.isEmpty {
            addToEnd(tracks: [track], startFromId: nil, clearQueue: false)
            return
        }
        
        // Insert after current index
        let insertIndex = currentIndex + 1
        queue.insert(track, at: insertIndex)
        originalQueue.append(track) // Append to original? Or insert? 
        // If shuffled, original order doesn't matter much for Play Next, 
        // but if un-shuffled, we expect it to be there. 
        // Ideally we insert it into originalQueue too? 
        // If we unshuffle we usually revert to originalQueue. 
        // So "Play Next" is a queue manipulation. 
        // For now append to original to keep it safe.
    }
    
    // ... (addToEnd implementation) ...
    
    func addToEnd(tracks: [Track], startFromId: String?, clearQueue: Bool) {
        if clearQueue {
            setQueue(tracks, startIndex: 0) // Should find startFromId index logic if needed, but simple for now
            // If startFromId provided, we should find it in the new tracks
            if let startId = startFromId, let index = tracks.firstIndex(where: { $0.id == startId }) {
                // If shuffle is on, we need to respect that.
                // setQueue handles playing at startIndex.
                // Re-call setQueue with correct index
                setQueue(tracks, startIndex: index)
            }
        } else {
            originalQueue.append(contentsOf: tracks)
            if shuffleMode {
                // Append random? Or just append and reshuffle?
                // Standard behavior: Append to queue, maybe shuffle the new part?
                // Simplest: Append to queue, don't reshuffle entire existing played history.
                // We just append to `queue` as well for now to keep it simple.
                queue.append(contentsOf: tracks)
            } else {
                queue.append(contentsOf: tracks)
            }
        }
        
        if !clearQueue, let startId = startFromId {
            // Find in current queue (which might be shuffled)
            if let index = queue.firstIndex(where: { $0.id == startId }) {
                playTrack(at: index, reason: .playlistChanged)
            }
        }
    }
    
    func setExecuteShuffleMode(_ enabled: Bool) {
        guard shuffleMode != enabled else { return }
        shuffleMode = enabled
        
        if enabled {
            // Turning shuffle ON
            shuffleQueue(keepCurrentIndex: currentIndex)
        } else {
            // Turning shuffle OFF
            // We need to find current track in originalQueue and set currentIndex there
            if currentIndex >= 0 && currentIndex < queue.count {
                let currentTrack = queue[currentIndex]
                queue = originalQueue
                if let newIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) {
                    currentIndex = newIndex
                } else {
                    currentIndex = 0 // Should not happen
                }
            } else {
                queue = originalQueue
                currentIndex = -1
            }
        }
        saveState()
    }
    
    func setExecuteRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        saveState()
    }
    
    private func shuffleQueue(keepCurrentIndex: Int) {
        guard !originalQueue.isEmpty else { return }
        
        if keepCurrentIndex >= 0 && keepCurrentIndex < originalQueue.count {
            let currentTrack = originalQueue[keepCurrentIndex] // Note: this index is relative to originalQueue if called from setQueue(shuffle=true)
            // Wait, if we are calling this from setQueue, `queue` might already be set to `tracks`.
            // Let's rely on `originalQueue` as source of truth.
            
            var remaining = originalQueue.filter { $0.id != currentTrack.id }
            remaining.shuffle()
            
            queue = [currentTrack] + remaining
            currentIndex = 0
        } else {
            queue = originalQueue.shuffled()
            currentIndex = -1
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        if player.currentItem == nil && currentIndex >= 0 {
             print("[OrpheusPlayer] play() called but currentItem is nil. Retrying track index \(currentIndex)")
             playTrack(at: currentIndex, reason: .auto)
             return
        }
        if player.status == .failed || player.currentItem?.status == .failed {
             print("[OrpheusPlayer] play() called but status is failed. Retrying track index \(currentIndex)")
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
        if queue.isEmpty { return }
        
        // If Repeat One, usually 'Next' button forces next track anyway, ignoring Repeat One.
        // Auto-advance respects Repeat One.
        // `skipToNext` is usually manual action. `handleAutoAdvance` calls this with reason=.auto
        
        var nextIndex = currentIndex + 1
        
        // Handle Cycle
        if nextIndex >= queue.count {
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
                 prevIndex = queue.count - 1
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
    
    private func playTrack(at index: Int, reason: TransitionReason) {
        guard index >= 0 && index < queue.count else {
            print("[OrpheusPlayer] playTrack: invalid index \(index), queue count: \(queue.count)")
            return
        }
        
        // Optimistic update
        self.currentIndex = index
        let track = queue[index]
        print("[OrpheusPlayer] playTrack: index=\(index), trackId=\(track.id), title=\(track.title ?? "nil")")
        onTrackStarted?(track.id, reason)
        saveState()
        
        let urlString = track.url
        print("[OrpheusPlayer] playTrack: url=\(urlString)")
        if urlString.starts(with: "orpheus://bilibili") {
            print("[OrpheusPlayer] playTrack: resolving bilibili URL...")
            resolveAndPlayBilibili(url: urlString)
        } else {
            print("[OrpheusPlayer] playTrack: loading direct URL...")
            loadAvPlayerItem(url: urlString, headers: nil)
        }
    }
    
    private func resolveAndPlayBilibili(url: String) {
        guard let uri = URL(string: url),
              let components = URLComponents(url: uri, resolvingAgainstBaseURL: false) else {
            print("[OrpheusPlayer] resolveAndPlayBilibili: failed to parse URL: \(url)")
            onPlayerError?("Invalid Bilibili URL")
            onPlaybackStateChanged?(.idle)
            return
        }
        
        let bvid = components.queryItems?.first(where: { $0.name == "bvid" })?.value
        let cid = components.queryItems?.first(where: { $0.name == "cid" })?.value
        
        guard let bvid = bvid else {
            print("[OrpheusPlayer] resolveAndPlayBilibili: missing bvid. url=\(url)")
            onPlayerError?("Missing bvid in URL")
            onPlaybackStateChanged?(.idle)
            return
        }
        
        if let cid = cid {
            fetchBilibiliPlayUrl(bvid: bvid, cid: cid)
        } else {
            print("[OrpheusPlayer] resolveAndPlayBilibili: missing cid, fetching page list...")
            BilibiliApi.shared.getPageList(bvid: bvid) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let cidInt):
                        print("[OrpheusPlayer] Got cid: \(cidInt)")
                        self?.fetchBilibiliPlayUrl(bvid: bvid, cid: String(cidInt))
                    case .failure(let error):
                        print("[OrpheusPlayer] resolveAndPlayBilibili: getPageList failed: \(error)")
                        self?.onPlayerError?(error.localizedDescription)
                        self?.onPlaybackStateChanged?(.idle)
                    }
                }
            }
        }
    }
    
    private func fetchBilibiliPlayUrl(bvid: String, cid: String) {
        print("[OrpheusPlayer] fetchBilibiliPlayUrl: bvid=\(bvid), cid=\(cid)")
        
        BilibiliApi.shared.getPlayUrl(bvid: bvid, cid: cid) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let realUrl):
                    print("[OrpheusPlayer] fetchBilibiliPlayUrl: got realUrl=\(realUrl.prefix(100))...")
                    // Bilibili requires Referer header
                    let headers: [String: String] = [
                        "Referer": "https://www.bilibili.com/",
                        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                    ]
                    self?.loadAvPlayerItem(url: realUrl, headers: headers)
                case .failure(let error):
                    print("[OrpheusPlayer] fetchBilibiliPlayUrl: FAILED - \(error)")
                    self?.onPlayerError?(error.localizedDescription)
                    // Reset state so UI doesn't stick in loading
                    self?.onPlaybackStateChanged?(.idle)
                }
            }
        }
    }
    
    private func loadAvPlayerItem(url: String, headers: [String: String]?) {
        guard let nsUrl = URL(string: url) else {
            print("[OrpheusPlayer] loadAvPlayerItem: invalid URL string: \(url)")
            return
        }
        
        print("[OrpheusPlayer] loadAvPlayerItem: creating asset with headers=\(headers != nil)")
        
        let asset: AVURLAsset
        if let headers = headers {
            let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            asset = AVURLAsset(url: nsUrl, options: options)
        } else {
            asset = AVURLAsset(url: nsUrl)
        }
        
        let item = AVPlayerItem(asset: asset)
        
        print("[OrpheusPlayer] loadAvPlayerItem: replacing current item and calling play()")
        player.replaceCurrentItem(with: item)
        player.play()
        
        print("[OrpheusPlayer] loadAvPlayerItem: player.rate=\(player.rate), timeControlStatus=\(player.timeControlStatus.rawValue)")
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
            print("[OrpheusPlayer] notifyPlaybackState: paused -> ready")
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
            // 打印等待原因
            if let reason = player.reasonForWaitingToPlay {
                print("[OrpheusPlayer] notifyPlaybackState: waiting -> buffering, reason=\(reason.rawValue)")
            } else {
                print("[OrpheusPlayer] notifyPlaybackState: waiting -> buffering, reason=nil")
            }
        case .playing:
            state = .ready
            print("[OrpheusPlayer] notifyPlaybackState: playing -> ready")
        @unknown default:
            state = .idle
            print("[OrpheusPlayer] notifyPlaybackState: unknown -> idle")
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
            print("Failed to setup audio session: \(error)")
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
        guard currentIndex >= 0 && currentIndex < queue.count else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        // Ensure audio session is active for lock screen controls to appear
        // Sometimes it gets deactivated on pause or background switch
        // do {
        //     try AVAudioSession.sharedInstance().setActive(true)
        // } catch {
        //     print("Failed to activate audio session for NowPlayingInfo: \(error)")
        // }
        // Note: Activating session repeatedly might be expensive, do it only if needed or keep it active.
        
        let track = queue[currentIndex]
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? "Unknown Title",
            MPMediaItemPropertyArtist: track.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count
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
        guard index >= 0 && index < queue.count else { return }
        playTrack(at: index, reason: .seek)
    }
    
    // MARK: - Playback Attributes
    
    func setPlaybackSpeed(_ speed: Float) {
        player.rate = speed
        // player.rate sets playing immediately if speed > 0
        // If paused, we might want to store it and apply when play? 
        // AVPlayer.rate implies playing. 
        // To change speed but keep pause state: 
        // player.defaultRate = speed (iOS 10+)? 
        // Actually typically valid user expectation: setting speed usually updates active rate.
        // But if paused? 
        if player.timeControlStatus == .paused {
             // Just property setting, don't play?
             // But AVPlayer.rate = x IS play()
             // We can use `player.audiovisualBackgroundPlaybackPolicy` or similar? 
             // Best practice: 
             // set rate to speed. If we were paused, pause again provided rate != 0?
        }
        // Simplified: set rate.
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
    
    private let KEY_SAVED_QUEUE = "saved_queue_json_list"
    private let KEY_SAVED_INDEX = "saved_index"
    private let KEY_SAVED_POSITION = "saved_position"
    private let KEY_SAVED_REPEAT_MODE = "saved_repeat_mode"
    private let KEY_SAVED_SHUFFLE_MODE = "saved_shuffle_mode"
    
    private func saveState() {
        let defaults = UserDefaults.standard
        
        // Save Queue (JSON list)
        // Convert [Track] to JSON strings using manual dictionary conversion
        do {
            let jsonList = try queue.compactMap { track -> String? in
                let dict = track.dictionaryRepresentation
                let data = try JSONSerialization.data(withJSONObject: dict, options: [])
                return String(data: data, encoding: .utf8)
            }
            defaults.set(jsonList, forKey: KEY_SAVED_QUEUE)
        } catch {
            print("[OrpheusPlayer] Failed to save queue: \(error)")
        }
        
        defaults.set(currentIndex, forKey: KEY_SAVED_INDEX)
        defaults.set(repeatMode.rawValue, forKey: KEY_SAVED_REPEAT_MODE)
        defaults.set(shuffleMode, forKey: KEY_SAVED_SHUFFLE_MODE)
        
        savePositionState()
    }
    
    private func savePositionState() {
        let seconds = player.currentTime().seconds
        if seconds.isNaN || seconds.isInfinite {
            return
        }
        let position = Int64(seconds * 1000)
        UserDefaults.standard.set(position, forKey: KEY_SAVED_POSITION)
    }

    private func restoreState() {
        let defaults = UserDefaults.standard
        
        // Restore Modes
        if let mode = RepeatMode(rawValue: defaults.integer(forKey: KEY_SAVED_REPEAT_MODE)) {
            repeatMode = mode
        }
        shuffleMode = defaults.bool(forKey: KEY_SAVED_SHUFFLE_MODE)
        
        // Restore Queue
        if let jsonList = defaults.stringArray(forKey: KEY_SAVED_QUEUE) {
            do {
                var restoredQueue: [Track] = []
                for jsonStr in jsonList {
                    if let data = jsonStr.data(using: .utf8),
                       let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let track = Track(dictionary: dict) {
                        restoredQueue.append(track)
                    }
                }
                
                if !restoredQueue.isEmpty {
                    originalQueue = restoredQueue
                    queue = restoredQueue 
                    originalQueue = restoredQueue // Fallback
                }
            } catch {
                print("[OrpheusPlayer] Failed to restore queue: \(error)")
            }
        }
        
        // Restore Index and Position
        let savedIndex = defaults.integer(forKey: KEY_SAVED_INDEX)
        let savedPosition = defaults.double(forKey: KEY_SAVED_POSITION) / 1000.0
        
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
                
                 onTrackStarted?(track.id, .playlistChanged)
                 
                 // If we want to be ready to play at position:
                 /*
                 let urlString = track.url
                 if !urlString.starts(with: "orpheus://bilibili") { // Skip async bili for startup perf?
                     let asset = AVURLAsset(url: URL(string: urlString)!)
                     let item = AVPlayerItem(asset: asset)
                     player.replaceCurrentItem(with: item)
                     player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 1000))
                     // player is paused by default
                 }
                 */
                 // Simple approach: restore indices, let UI show it. 
                 // Updating position might be tricky if player is empty.
                 // We can emit a position update manually?
                 onPositionUpdate?(savedPosition, track.duration ?? 0, 0)
            }
        }
    }
}
