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
    
    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
        donateAllPlaylists()
    }
    
    private func loadPlaylists() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            // Fixup video IDs: The sandbox container path changes on every launch.
            // Video IDs are based on url.absoluteString which includes the full path.
            // We need to rebuild video IDs based on the current Documents directory path.
            if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                playlists = decoded.map { playlist in
                    let updatedVideoIds = playlist.videoIds.map { oldId in
                        // Extract filename from old URL
                        if let oldURL = URL(string: oldId) {
                            let fileName = oldURL.lastPathComponent
                            let newURL = documents.appendingPathComponent(fileName)
                            return newURL.absoluteString
                        }
                        return oldId
                    }
                    return Playlist(id: playlist.id, name: playlist.name, videoIds: updatedVideoIds)
                }
            } else {
                playlists = decoded
            }
        }
    }
}
