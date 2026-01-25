import Foundation
import AVFoundation
import Foundation
import AVFoundation
import SwiftUI
import Combine

class VideoManager: ObservableObject {
    static let shared = VideoManager()
    @Published var videos: [Video] = []
    @Published var isLoading = false
    
    init() {
        loadVideosFromDisk()
    }
    
    private var persistenceURL: URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return appSupportURL.appendingPathComponent("videos.json")
    }
    
    private func migratePersistenceIfNeeded() {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let oldURL = documents.appendingPathComponent("videos.json")
        
        guard fileManager.fileExists(atPath: oldURL.path) else { return }
        guard let newURL = persistenceURL else { return }
        
        do {
            if fileManager.fileExists(atPath: newURL.path) {
                try fileManager.removeItem(at: oldURL)
            } else {
                try fileManager.moveItem(at: oldURL, to: newURL)
            }
            print("Successfully migrated persistence file to \(newURL.path)")
        } catch {
            print("Failed to migrate persistence file: \(error)")
        }
    }
    
    func saveVideosToDisk() {
        guard let url = persistenceURL else { return }
        do {
            let data = try JSONEncoder().encode(videos)
            try data.write(to: url)
        } catch {
            print("Failed to save videos: \(error)")
        }
    }
    
    private func loadVideosFromDisk() {
        migratePersistenceIfNeeded()
        guard let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([Video].self, from: data)
            
            // Fixup URLs: The sandbox container path changes on every launch.
            // We need to re-point the URL to the current Documents directory.
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                self.videos = loaded.map { video in
                    let fileName = video.url.lastPathComponent
                    let newURL = documents.appendingPathComponent(fileName)
                    
                    // If fileSize is 0 (or wasn't in original JSON), try to get it now
                    var size = video.fileSize
                    if size == 0 {
                        let resources = try? newURL.resourceValues(forKeys: [.fileSizeKey])
                        size = Int64(resources?.fileSize ?? 0)
                    }
                    
                    return Video(name: video.name, url: newURL, duration: video.duration, dateAdded: video.dateAdded, fileSize: size, isWatched: video.isWatched, watchCount: video.watchCount)
                }
            } else {
                self.videos = loaded
            }
        } catch {
            print("Failed to load videos: \(error)")
        }
    }
    
    private func setupDocumentsDirectory() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // Write a persistent file so the folder appears in Files app
        let readmeURL = documentsURL.appendingPathComponent("README.txt")
        print("Seting up Documents Directory at: \(documentsURL.path)")
        if !fileManager.fileExists(atPath: readmeURL.path) {
            let content = "Put your .mp4, .mov, .m4v video files in this folder to play them in Vid."
            do {
                try content.write(to: readmeURL, atomically: true, encoding: .utf8)
                print("Successfully wrote README.txt to \(readmeURL.path)")
            } catch {
                print("Failed to write README.txt: \(error)")
            }
        } else {
            print("README.txt already exists at \(readmeURL.path)")
        }
    }
    
    func loadVideos() {
        Task {
            await loadVideosAsync()
        }
    }
    
    @MainActor
    func loadVideosAsync() async {
        guard !isLoading else { return }
        isLoading = true
        // Do not clear videos to avoid flash
        
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            isLoading = false
            return
        }
        
        let fileManager = FileManager.default
        
        do {
            let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey]
            let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
            
            var loadedVideos: [Video] = []
            
            // Collect URLs first to avoid blocking main thread too long if we were on it (but we are async)
            // Enumeration is synchronous on file system usually.
            
            var videoURLs: [URL] = []
            if let enumerator = enumerator {
                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                       resourceValues.isDirectory == true { continue }
                    
                    if ["mp4", "mov", "m4v"].contains(fileURL.pathExtension.lowercased()) {
                        videoURLs.append(fileURL)
                    }
                }
            }
            
            for url in videoURLs {
                let asset = AVURLAsset(url: url)
                // load(.duration) is async
                let durationTime = asset.duration
                let duration = CMTimeGetSeconds(durationTime)
                // Important: We need a stable ID logic if we want playlists to survive reloads.
                // But for now, we follow the existing pattern, just fixing the reload behavior.

                // Check if this video already exists to preserve its dateAdded
                let existingVideo = self.videos.first(where: { $0.url.lastPathComponent == url.lastPathComponent })
                let dateAdded = existingVideo?.dateAdded ?? Date()

                // Get file size
                let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resources?.fileSize ?? 0)

                // Get watched state if exists
                let isWatched = existingVideo?.isWatched ?? false
                let watchCount = existingVideo?.watchCount ?? 0

                let video = Video(name: url.deletingPathExtension().lastPathComponent, url: url, duration: duration, dateAdded: dateAdded, fileSize: fileSize, isWatched: isWatched, watchCount: watchCount)
                loadedVideos.append(video)
            }
            
            // Sort
            let finalVideos = loadedVideos.sorted { $0.name < $1.name }
            
            // Update State
            await MainActor.run {
                self.videos = finalVideos
                self.isLoading = false
                self.saveVideosToDisk()
                // After loading, prune stale references in playlists and likes
                let validIds = Set(self.videos.map { $0.id })
                PlaylistManager.shared.pruneMissingVideoIds(validIds: validIds)
                SettingsStore.shared.pruneMissingLikes(validIds: validIds)
            }
            
        } catch {
            print("Error loading videos: \(error)")
            self.isLoading = false
        }
    }

    
    func importFiles(_ urls: [URL]) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Failed to import file: \(error)")
            }
        }
        
        loadVideos()
    }
}
