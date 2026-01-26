import Foundation
import SwiftUI
import Combine

class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()
    @Published var playlists: [Playlist] = []
    
    private let saveKey = "saved_playlists"
    
    init() {
        loadPlaylists()
        donateAllPlaylists()
    }
    
    private func donateAllPlaylists() {
        for playlist in playlists {
            let activity = NSUserActivity(activityType: "com.vid.playPlaylist")
            activity.title = "Play playlist \(playlist.name)"
            if Locale.current.identifier.contains("es") {
                activity.title = "Reproducir lista \(playlist.name)"
            }
            activity.userInfo = ["playlistId": playlist.id.uuidString]
            activity.isEligibleForPrediction = true
            activity.isEligibleForSearch = true
            activity.persistentIdentifier = NSUserActivityPersistentIdentifier("playlist_\(playlist.id.uuidString)")
            activity.becomeCurrent()
        }
    }
    
    func createPlaylist(name: String) {
        let newPlaylist = Playlist(name: name, videoIds: [])
        playlists.append(newPlaylist)
        savePlaylists()
    }
    
    func deletePlaylist(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        savePlaylists()
    }
    
    func addVideos(_ videos: [Video], to playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        var currentVideoIds = playlists[index].videoIds
        for video in videos {
            if !currentVideoIds.contains(video.id) {
                currentVideoIds.append(video.id)
            }
        }
        playlists[index].videoIds = currentVideoIds
        savePlaylists()
    }
    
    func removeVideo(id: String, from playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if let videoIndex = playlists[index].videoIds.firstIndex(of: id) {
            playlists[index].videoIds.remove(at: videoIndex)
            savePlaylists()
        }
    }

    /// Remove any video IDs from all playlists that are not present in `validIds`.
    /// Also updates video IDs to match the current valid IDs (handles sandbox path changes).
    func pruneMissingVideoIds(validIds: Set<String>) {
        // Build a map from filename to valid ID for fast lookup
        // This handles the case where /var vs /private/var paths differ
        var filenameToValidId: [String: String] = [:]
        for validId in validIds {
            if let url = URL(string: validId) {
                filenameToValidId[url.lastPathComponent] = validId
            }
        }

        var changed = false
        for i in playlists.indices {
            let original = playlists[i].videoIds
            var updated: [String] = []

            for videoId in original {
                // Extract filename from the stored video ID
                if let url = URL(string: videoId) {
                    let filename = url.lastPathComponent
                    // If we have a valid ID for this filename, use it (this handles path changes)
                    if let matchedValidId = filenameToValidId[filename] {
                        updated.append(matchedValidId)
                    }
                    // Otherwise, the video no longer exists - skip it
                }
            }

            if updated != original {
                playlists[i].videoIds = updated
                changed = true
            }
        }
        if changed { savePlaylists() }
    }
    
    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
        donateAllPlaylists()
    }
    
    private func loadPlaylists() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            // Load playlists as-is. The pruneMissingVideoIds() function will be called
            // after VideoManager loads videos and will update the video IDs to match
            // the current valid IDs (handling sandbox path changes).
            playlists = decoded
        }
    }
}
