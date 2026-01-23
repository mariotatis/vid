import SwiftUI

struct MainTabView: View {
    @StateObject var videoManager = VideoManager.shared
    @StateObject var playlistManager = PlaylistManager.shared
    @StateObject var settingsStore = SettingsStore.shared
    @StateObject var playerVM = PlayerViewModel.shared
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                AllVideosView(videoManager: videoManager, settings: settingsStore)
                    .tabItem {
                        Label("Library", systemImage: "play.rectangle.on.rectangle")
                    }
                    .tag(0)

                PlaylistsView(playlistManager: playlistManager, videoManager: videoManager, settings: settingsStore)
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                    .tag(1)
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
            donateGenericActivities()
        }
        .onContinueUserActivity("com.vid.playPlaylist") { activity in
            handlePlayPlaylistActivity(activity)
        }
    }
    
    private func handlePlayPlaylistActivity(_ activity: NSUserActivity) {
        if let playlistIdString = activity.userInfo?["playlistId"] as? String,
           let playlistId = UUID(uuidString: playlistIdString) {
            
            // Find playlist
            if let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                let resolvedVideos = playlist.videoIds.compactMap { id in
                    videoManager.videos.first(where: { $0.id == id })
                }
                if let firstVideo = resolvedVideos.first {
                    playerVM.play(video: firstVideo, from: resolvedVideos, settings: settingsStore)
                }
            }
        } else if let videoUrlString = activity.userInfo?["videoUrl"] as? String,
                  let videoUrl = URL(string: videoUrlString) {
            // Handle single video donation
            if let video = videoManager.videos.first(where: { $0.url == videoUrl }) {
                playerVM.play(video: video, from: videoManager.videos, settings: settingsStore)
            }
        }
    }
    
    private func autoPlayLastContext() {
        guard settingsStore.autoplayOnAppOpen && settingsStore.lastContextType != "" else { return }

        // Use a small delay to ensure VideoManager and PlaylistManager have finished their initial local disk load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Find the last played video
            let lastVideo = videoManager.videos.first(where: { $0.id == settingsStore.lastVideoId })

            if settingsStore.lastContextType == "all" {
                selectedTab = 0
                // Try to play the last video, fallback to first video if not found
                let videoToPlay = lastVideo ?? videoManager.videos.first
                if let video = videoToPlay {
                    playerVM.play(video: video, from: videoManager.videos, settings: settingsStore)
                }
            } else if settingsStore.lastContextType == "playlist",
                      let playlistId = UUID(uuidString: settingsStore.lastPlaylistId) {
                selectedTab = 1
                if let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                    let resolvedVideos = playlist.videoIds.compactMap { id in
                        videoManager.videos.first(where: { $0.id == id })
                    }
                    // Try to play the last video if it's in this playlist, otherwise play first video
                    let videoToPlay = (lastVideo != nil && resolvedVideos.contains(where: { $0.id == lastVideo?.id }))
                        ? lastVideo
                        : resolvedVideos.first
                    if let video = videoToPlay {
                        playerVM.play(video: video, from: resolvedVideos, settings: settingsStore)
                    }
                }
            }
        }
    }

    private func donateGenericActivities() {
        // 1. Search Activity
        let searchActivity = NSUserActivity(activityType: "com.vid.searchVideos")
        searchActivity.title = "Search a Video on Vid"
        if Locale.current.identifier.contains("es") {
            searchActivity.title = "Buscar videos en Vid"
        }
        searchActivity.isEligibleForSearch = true
        searchActivity.isEligibleForPrediction = true
        searchActivity.becomeCurrent()
        
        // 2. Play Playlist Activity
        let playlistActivity = NSUserActivity(activityType: "com.vid.playPlaylist")
        playlistActivity.title = "Play a playlist on Vid"
        if Locale.current.identifier.contains("es") {
            playlistActivity.title = "Reproducir una lista en Vid"
        }
        playlistActivity.isEligibleForSearch = true
        playlistActivity.isEligibleForPrediction = true
        playlistActivity.becomeCurrent()
    }
}
