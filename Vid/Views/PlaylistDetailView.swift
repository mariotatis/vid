import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @EnvironmentObject var playerVM: PlayerViewModel
    @ObservedObject var settings: SettingsStore
    @FocusState private var focusedElement: AppFocus?
    
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
    
    var body: some View {
        Group {
            if resolvedVideos.isEmpty {
                VStack {
                    Text("No videos in this playlist.")
                    Text("Tap + to add videos.")
                        .foregroundColor(.secondary)
                }
            } else {
                VideoListView(videos: resolvedVideos, focusedElement: $focusedElement, onDelete: { offsets in deleteVideo(at: offsets) }, onPlay: { video in
                    settings.lastContextType = "playlist"
                    settings.lastPlaylistId = playlist.id.uuidString
                    playerVM.play(video: video, from: resolvedVideos, settings: settings)
                })
            }
        }
        .navigationTitle(livePlaylist.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AddVideosToPlaylistView(playlistId: playlist.id, videoManager: videoManager, playlistManager: playlistManager)) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .vidFocusHighlight()
                }
                .buttonStyle(VidButtonStyle())
                .focused($focusedElement, equals: .search)
            }
        }
        .onAppear {
            if focusedElement == nil {
                if let firstId = resolvedVideos.first?.id {
                    focusedElement = .videoItem(firstId)
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
