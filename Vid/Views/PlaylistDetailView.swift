import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @EnvironmentObject var playerVM: PlayerViewModel
    @ObservedObject var settingsStore: SettingsStore
    
    // We need to resolve videoIds to Video objects.
    // Since Playlist is a Struct (value type), and we want to know when it updates (though the list passed in is static value).
    // We rely on `playlistManager` updates. We need to find the current playlist in the manager.
    
    var livePlaylist: Playlist {
        playlistManager.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }
    
    var resolvedVideos: [Video] {
        livePlaylist.videoIds.compactMap { id in
            videoManager.videos.first(where: { $0.id == id })
        }
    }
    
    init(playlist: Playlist, playlistManager: PlaylistManager, videoManager: VideoManager, settings: SettingsStore) {
        self.playlist = playlist
        self.playlistManager = playlistManager
        self.videoManager = videoManager
        self.settingsStore = settings
    }
    
    var body: some View {
        Group {
            if resolvedVideos.isEmpty {
                VStack {
                    Text("No videos in this playlist.")
                    Text("Tap + to add videos.")
                        .foregroundColor(.secondary)
                }
            } else {
                VideoListView(videos: resolvedVideos, onDelete: deleteVideo, onPlay: { video in
                    playerVM.play(video: video, from: resolvedVideos, settings: settingsStore)
                })
            }
        }
        .navigationTitle(livePlaylist.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AddVideosToPlaylistView(playlistId: playlist.id, videoManager: videoManager, playlistManager: playlistManager)) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    func deleteVideo(at offsets: IndexSet) {
        let idsToRemove = offsets.map { resolvedVideos[$0].id }
        for id in idsToRemove {
            playlistManager.removeVideo(id: id, from: playlist.id)
        }
    }
}
