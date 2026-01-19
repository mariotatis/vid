import Foundation
import SwiftUI
import Combine

class PlaylistManager: ObservableObject {
    @Published var playlists: [Playlist] = []
    
    private let saveKey = "saved_playlists"
    
    init() {
        loadPlaylists()
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
    }
    
    private func loadPlaylists() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }
}
