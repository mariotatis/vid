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
    }
}
