import Foundation

class GeneralStorage {
    static let shared = GeneralStorage()
    
    private let defaults = UserDefaults.standard
    
    private let KEY_SAVED_QUEUE = "saved_queue_json_list"
    private let KEY_SAVED_INDEX = "saved_index"
    private let KEY_SAVED_POSITION = "saved_position"
    private let KEY_SAVED_REPEAT_MODE = "saved_repeat_mode"
    private let KEY_SAVED_SHUFFLE_MODE = "saved_shuffle_mode"
    
    private let KEY_RESTORE_ENABLED = "restorePlaybackPositionEnabled"
    private let KEY_LOUDNESS_ENABLED = "loudnessNormalizationEnabled"
    private let KEY_AUTOPLAY_ENABLED = "autoplayOnStartEnabled"
    private let KEY_DESKTOP_LYRICS_SHOWN = "isDesktopLyricsShown" // Not really used in iOS but following pattern
    private let KEY_DESKTOP_LYRICS_LOCKED = "isDesktopLyricsLocked"
    
    // MARK: - Preferences
    
    var isRestoreEnabled: Bool {
        get { return defaults.bool(forKey: KEY_RESTORE_ENABLED) }
        set { defaults.set(newValue, forKey: KEY_RESTORE_ENABLED) }
    }
    
    var isLoudnessNormalizationEnabled: Bool {
        get { return defaults.bool(forKey: KEY_LOUDNESS_ENABLED) }
        set { defaults.set(newValue, forKey: KEY_LOUDNESS_ENABLED) }
    }
    
    var isAutoplayOnStartEnabled: Bool {
        get { return defaults.bool(forKey: KEY_AUTOPLAY_ENABLED) }
        set { defaults.set(newValue, forKey: KEY_AUTOPLAY_ENABLED) }
    }
    
    // MARK: - Playback State
    
    func saveQueue(_ queue: [Track]) {
        do {
            let jsonList = try queue.compactMap { track -> String? in
                let dict = track.dictionaryRepresentation
                let data = try JSONSerialization.data(withJSONObject: dict, options: [])
                return String(data: data, encoding: .utf8)
            }
            defaults.set(jsonList, forKey: KEY_SAVED_QUEUE)
        } catch {

        }
    }
    
    func getSavedQueue() -> [Track] {
        guard let jsonList = defaults.stringArray(forKey: KEY_SAVED_QUEUE) else { return [] }
        
        var restoredQueue: [Track] = []
        for jsonStr in jsonList {
            if let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let track = Track(dictionary: dict) {
                restoredQueue.append(track)
            }
        }
        return restoredQueue
    }
    
    func savePosition(index: Int, positionSec: Double) {
        defaults.set(index, forKey: KEY_SAVED_INDEX)
        
        if !positionSec.isNaN && !positionSec.isInfinite {
             let positionMs = Int64(positionSec * 1000)
             defaults.set(positionMs, forKey: KEY_SAVED_POSITION)
        }
    }
    
    func getSavedIndex() -> Int {
        return defaults.integer(forKey: KEY_SAVED_INDEX)
    }
    
    func getSavedPosition() -> Double {
        return defaults.double(forKey: KEY_SAVED_POSITION) / 1000.0
    }
    
    func saveRepeatMode(_ mode: Int) {
        defaults.set(mode, forKey: KEY_SAVED_REPEAT_MODE)
    }
    
    func getSavedRepeatMode() -> Int {
        return defaults.integer(forKey: KEY_SAVED_REPEAT_MODE)
    }
    
    func saveShuffleMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: KEY_SAVED_SHUFFLE_MODE)
    }
    
    func getSavedShuffleMode() -> Bool {
        return defaults.bool(forKey: KEY_SAVED_SHUFFLE_MODE)
    }
}
