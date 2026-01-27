import Foundation
import ExpoModulesCore
import MMKV

class OrpheusDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = OrpheusDownloadManager()
    
    private var urlSession: URLSession!
    private var downloadTasks: [String: DownloadState] = [:] // Map taskID/url to state
    private var activeTasks: [String: URLSessionDownloadTask] = [:] // Map ID to task
    private var trackMap: [String: Track] = [:] // Map ID to Track metadata
    var onDownloadUpdated: ((DownloadTask) -> Void)?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.orpheus.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        restoreTasks()
    }
    
    func downloadTrack(track: Track) {
        // Resolve URL if needed (Bilibili logic)
        let urlString = track.url
        if urlString.starts(with: "orpheus://bilibili") {
            resolveAndDownload(track: track)
        } else {
            startDownload(url: urlString, track: track)
        }
    }
    
    private func resolveAndDownload(track: Track) {
        guard let uri = URL(string: track.url),
              let components = URLComponents(url: uri, resolvingAgainstBaseURL: false) else { return }
        
        let bvid = components.queryItems?.first(where: { $0.name == "bvid" })?.value
        let cid = components.queryItems?.first(where: { $0.name == "cid" })?.value
        
        guard let bvid = bvid, let cid = cid else { return }
        
        BilibiliApi.shared.getPlayUrl(bvid: bvid, cid: cid) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let realUrl):
                    self?.startDownload(url: realUrl, track: track)
                case .failure(let error):
                    self?.notifyUpdate(id: track.id, state: .failed, track: track)
                }
            }
        }
    }
    
    private func notifyUpdate(id: String, state: DownloadState, track: Track?) {
        let task = DownloadTask()
        task.id = id
        task.state = state
        task.track = track
        
        if state == .completed {
            task.percentDownloaded = 1.0
        }
        
        onDownloadUpdated?(task)
    }
        private func startDownload(url: String, track: Track) {

        guard let nsUrl = URL(string: url) else { return }
        var request = URLRequest(url: nsUrl)
        if url.contains("bilivideo.com") {
             request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
             request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        }
        
        let task = urlSession.downloadTask(with: request)
        task.taskDescription = track.id
        
        trackMap[track.id] = track
        activeTasks[track.id] = task
        downloadTasks[track.id] = .downloading
        
        task.resume()
        
        saveTasks()
        notifyUpdate(id: track.id, state: .downloading, track: track)
    }
    
    func removeDownload(id: String) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        

        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent("downloads/\(id).mp4")
        try? fileManager.removeItem(at: dest)
        
        downloadTasks.removeValue(forKey: id)
        trackMap.removeValue(forKey: id)
        
        saveTasks()
        notifyUpdate(id: id, state: .removing, track: nil)
    }
    
    func removeAllDownloads() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = docs.appendingPathComponent("downloads")
        try? fileManager.removeItem(at: downloadsDir)
        
        downloadTasks.removeAll()
        trackMap.removeAll()
        
        saveTasks()
    }
    
    // MARK: - Persistence
    
    private let KEY_SAVED_TASKS = "saved_download_tasks"
    
    private struct SavedTrack: Codable {
        let id: String
        let url: String
        let title: String?
        let artist: String?
        let artwork: String?
        let duration: Double?
    }
    
    private struct PersistedTask: Codable {
        let id: String
        let state: Int
        let track: SavedTrack
    }
    

    private func toSavedTrack(_ track: Track) -> SavedTrack {
        return SavedTrack(
            id: track.id,
            url: track.url,
            title: track.title,
            artist: track.artist,
            artwork: track.artwork,
            duration: track.duration,
        )
    }
    
    private func fromSavedTrack(_ saved: SavedTrack) -> Track {
        let t = Track()
        t.id = saved.id
        t.url = saved.url
        t.title = saved.title
        t.artist = saved.artist
        t.artwork = saved.artwork
        t.duration = saved.duration
        return t
    }
    
    private func saveTasks() {
        let tasksToSave = trackMap.map { (id, track) -> PersistedTask in
            let state = downloadTasks[id] ?? .queued
            return PersistedTask(id: id, state: state.rawValue, track: toSavedTrack(track))
        }
        
        if let data = try? JSONEncoder().encode(tasksToSave) {
            MMKV.default()?.set(data, forKey: KEY_SAVED_TASKS)
        }
    }
    
    private func restoreTasks() {
        guard let data = MMKV.default()?.data(forKey: KEY_SAVED_TASKS),
              let persisted = try? JSONDecoder().decode([PersistedTask].self, from: data) else {
            return
        }
            
        for p in persisted {
            let track = fromSavedTrack(p.track)
            trackMap[p.id] = track
            if let state = DownloadState(rawValue: p.state) {
                downloadTasks[p.id] = state
            }
        }
        
        // Check for existing background tasks first
        urlSession.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                var runningTaskIds = Set<String>()
                
                for task in tasks {
                    if let dlTask = task as? URLSessionDownloadTask, let id = dlTask.taskDescription {
                        self.activeTasks[id] = dlTask
                        runningTaskIds.insert(id)
                        
                        // Update state to downloading if it was running
                        if dlTask.state == .running {
                            self.downloadTasks[id] = .downloading
                        }
                    }
                }
                
                // Auto-resume downloads that should be running but aren't
                for (id, state) in self.downloadTasks {
                    if state == .downloading && !runningTaskIds.contains(id) {
                        // User might have force quit app or system killed it while not strictly in background task?
                        // Restart download
                        if let track = self.trackMap[id] {
                            self.downloadTrack(track: track)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Delegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = docs.appendingPathComponent("downloads")
        
        do {
            try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            // Use mp4 for now. Ideally retain extension from url or metadata.
            let dest = downloadsDir.appendingPathComponent("\(id).mp4")
            
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.moveItem(at: location, to: dest)
            
            downloadTasks[id] = .completed
            activeTasks.removeValue(forKey: id)
            saveTasks()
            
            if let track = trackMap[id] {
                notifyUpdate(id: id, state: .completed, track: track)
            }
        } catch {

            downloadTasks[id] = .failed
            saveTasks()
            notifyUpdate(id: id, state: .failed, track: trackMap[id])
        }
    }
    

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        
        if let error = error {

            if (error as NSError).code == NSURLErrorCancelled {
                downloadTasks[id] = .stopped
            } else {
                downloadTasks[id] = .failed
                notifyUpdate(id: id, state: .failed, track: trackMap[id])
            }
            activeTasks.removeValue(forKey: id)
            saveTasks()
        }
    }
    
    func getDownloads() -> [DownloadTask] {
        return trackMap.map { (id, track) -> DownloadTask in
            let task = DownloadTask()
            task.id = id
            task.state = downloadTasks[id] ?? .queued
            task.track = track
            
            if task.state == .completed {
                task.percentDownloaded = 1.0
                task.contentLength = 0
                let fileManager = FileManager.default
                let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dest = docs.appendingPathComponent("downloads/\(id).mp4")
                if let attrs = try? fileManager.attributesOfItem(atPath: dest.path),
                   let size = attrs[.size] as? Double {
                    task.contentLength = size
                    task.bytesDownloaded = size
                }
            } else if let active = activeTasks[id] {

                task.bytesDownloaded = Double(active.countOfBytesReceived)
                task.contentLength = Double(active.countOfBytesExpectedToReceive)
                task.percentDownloaded = task.contentLength > 0 ? task.bytesDownloaded / task.contentLength : 0
            }
            
            return task
        }
    }
    
    func multiDownload(tracks: [Track]) {
        for track in tracks {
            downloadTrack(track: track)
        }
    }
    
    func getDownloadStatusByIds(ids: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for id in ids {
            if let state = downloadTasks[id] {
                result[id] = state.rawValue
            }
        }
        return result
    }
    
    func clearUncompletedTasks() {
        for (id, state) in downloadTasks {
            if state != .completed {
                removeDownload(id: id)
            }
        }
    }
    
    func getUncompletedTasks() -> [DownloadTask] {
        return getDownloads().filter { $0.state != .completed }
    }
    
    func getDownloadedFileUrl(id: String) -> URL? {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent("downloads/\(id).mp4")
        
        if fileManager.fileExists(atPath: dest.path) {
            return dest
        }
        return nil
    }
}
