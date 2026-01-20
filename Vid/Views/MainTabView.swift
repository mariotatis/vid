import SwiftUI

struct MainTabView: View {
    @StateObject var videoManager = VideoManager()
    @StateObject var playlistManager = PlaylistManager()
    @StateObject var settingsStore = SettingsStore()
    @StateObject var playerVM = PlayerViewModel()
    
    var body: some View {
        ZStack {
            TabView {
                AllVideosView(videoManager: videoManager, settings: settingsStore)
                    .tabItem {
                        Label("All", systemImage: "play.rectangle.on.rectangle")
                    }
                
                PlaylistsView(playlistManager: playlistManager, videoManager: videoManager, settings: settingsStore)
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }
            }
            .environmentObject(playerVM)
            
            // Full Screen Player Overlay
            if playerVM.showPlayer {
                PlayerView()
                    .environmentObject(playerVM)
                    .environmentObject(settingsStore)
                    .transition(.move(edge: .bottom))
                    .zIndex(1) // Ensure it's on top
            }
        }
        .onAppear {
            autoPlayLastContext()
        }
    }
    
    private func autoPlayLastContext() {
        guard settingsStore.lastContextType != "" else { return }
        
        // Use a small delay to ensure VideoManager and PlaylistManager have finished their initial local disk load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if settingsStore.lastContextType == "all" {
                if let firstVideo = videoManager.videos.first {
                    playerVM.play(video: firstVideo, from: videoManager.videos, settings: settingsStore)
                }
            } else if settingsStore.lastContextType == "playlist",
                      let playlistId = UUID(uuidString: settingsStore.lastPlaylistId) {
                if let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                    let resolvedVideos = playlist.videoIds.compactMap { id in
                        videoManager.videos.first(where: { $0.id == id })
                    }
                    if let firstVideo = resolvedVideos.first {
                        playerVM.play(video: firstVideo, from: resolvedVideos, settings: settingsStore)
                    }
                }
            }
        }
    }
}
