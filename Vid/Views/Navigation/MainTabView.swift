import SwiftUI
import UniformTypeIdentifiers

struct MainTabView: View {
    @StateObject var videoManager = VideoManager.shared
    @StateObject var playlistManager = PlaylistManager.shared
    @StateObject var settingsStore = SettingsStore.shared
    @StateObject var playerVM = PlayerViewModel.shared
    @State private var selectedTab: NavigationTab = .library

    // Library state
    @State private var showFileImporter = false
    @State private var showSearch = false

    // Playlist state
    @State private var showCreatePlaylist = false
    @State private var showSettings = false

    // Navigation state for returning to playlist after closing player
    @State private var navigateToPlaylistId: UUID?
    @State private var navigateToLiked: Bool = false

    var onAppLoaded: (() -> Void)?

    var body: some View {
        contentView
        .environmentObject(playerVM)
        .fullScreenCover(isPresented: $playerVM.showPlayer) {
            PlayerView()
                .environmentObject(playerVM)
                .environmentObject(settingsStore)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                videoManager.importFiles(urls)
            case .failure(let error):
                print("Vid: Error importing files: \(error.localizedDescription)")
            }
        }
        .alert("New Playlist", isPresented: $showCreatePlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    playlistManager.createPlaylist(name: newPlaylistName)
                    newPlaylistName = ""
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settingsStore)
        }
        .onAppear {
            onAppLoaded?()
            autoPlayLastContext()
            donateGenericActivities()
        }
        .onChange(of: playerVM.showPlayer) { isShowing in
            if !isShowing {
                // Player was closed - navigate to the appropriate context
                navigateToContextAfterPlayerClose()
            }
        }
        .onContinueUserActivity("com.vid.playPlaylist") { activity in
            handlePlayPlaylistActivity(activity)
        }
    }

    @State private var newPlaylistName = ""

    private var hasPlaylistContent: Bool {
        !settingsStore.likedVideoIds.isEmpty || !playlistManager.playlists.isEmpty
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .library:
            AllVideosView(
                videoManager: videoManager,
                settings: settingsStore,
                selectedTab: $selectedTab,
                showSearch: $showSearch,
                onAddVideo: { showFileImporter = true },
                onAddPlaylist: { showCreatePlaylist = true },
                onOpenSettings: { showSettings = true },
                hasPlaylistContent: hasPlaylistContent,
                sortMenuContent: { AnyView(librarySortMenu) },
                viewStyleMenuContent: { AnyView(playlistViewMenu) }
            )
        case .playlists:
            PlaylistsView(
                playlistManager: playlistManager,
                videoManager: videoManager,
                settings: settingsStore,
                selectedTab: $selectedTab,
                navigateToPlaylistId: $navigateToPlaylistId,
                navigateToLiked: $navigateToLiked,
                onAddVideo: { showFileImporter = true },
                onAddPlaylist: { showCreatePlaylist = true },
                onOpenSettings: { showSettings = true },
                hasPlaylistContent: hasPlaylistContent,
                sortMenuContent: { AnyView(librarySortMenu) },
                viewStyleMenuContent: { AnyView(playlistViewMenu) }
            )
        }
    }

    // MARK: - Sort Menu for Library

    @AppStorage("librarySortOption") private var sortOptionRaw: String = "name"
    @AppStorage("librarySortAscending") private var sortAscending: Bool = true

    @ViewBuilder
    private var librarySortMenu: some View {
        Section {
            Button(action: { sortOptionRaw = "name"; sortAscending = true }) {
                Label("Name", systemImage: sortOptionRaw == "name" ? "checkmark" : "")
            }
            Button(action: { sortOptionRaw = "duration"; sortAscending = false }) {
                Label("Duration", systemImage: sortOptionRaw == "duration" ? "checkmark" : "")
            }
            Button(action: { sortOptionRaw = "recent"; sortAscending = false }) {
                Label("Recent", systemImage: sortOptionRaw == "recent" ? "checkmark" : "")
            }
            Button(action: { sortOptionRaw = "size"; sortAscending = false }) {
                Label("Size", systemImage: sortOptionRaw == "size" ? "checkmark" : "")
            }
            Button(action: { sortOptionRaw = "mostWatched"; sortAscending = false }) {
                Label("Most Watched", systemImage: sortOptionRaw == "mostWatched" ? "checkmark" : "")
            }
        }

        Divider()

        Section {
            Button(action: { sortAscending = true }) {
                Label("Ascending", systemImage: sortAscending ? "checkmark" : "")
            }
            Button(action: { sortAscending = false }) {
                Label("Descending", systemImage: !sortAscending ? "checkmark" : "")
            }
        }

    }

    // MARK: - View Style Menu for Playlists

    @AppStorage("playlistViewStyle") private var viewStyle: PlaylistViewStyle = .grid

    @ViewBuilder
    private var playlistViewMenu: some View {
        Button(action: { viewStyle = .list }) {
            Label("List View", systemImage: viewStyle == .list ? "checkmark" : "")
        }
        Button(action: { viewStyle = .grid }) {
            Label("Grid View", systemImage: viewStyle == .grid ? "checkmark" : "")
        }
    }

    // MARK: - Activity Handlers

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
            if settingsStore.lastContextType == "all" {
                selectedTab = .library
                // Play a random video from the library
                if let video = videoManager.videos.randomElement() {
                    playerVM.play(video: video, from: videoManager.videos, settings: settingsStore)
                }
            } else if settingsStore.lastContextType == "liked" {
                selectedTab = .playlists
                // Get liked videos and play a random one
                let likedVideos = videoManager.videos.filter { settingsStore.likedVideoIds.contains($0.id) }
                if let video = likedVideos.randomElement() {
                    playerVM.play(video: video, from: likedVideos, settings: settingsStore)
                }
            } else if settingsStore.lastContextType == "playlist",
                      let playlistId = UUID(uuidString: settingsStore.lastPlaylistId) {
                selectedTab = .playlists
                if let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                    let resolvedVideos = playlist.videoIds.compactMap { id in
                        videoManager.videos.first(where: { $0.id == id })
                    }
                    // Play a random video from the playlist
                    if let video = resolvedVideos.randomElement() {
                        playerVM.play(video: video, from: resolvedVideos, settings: settingsStore)
                    }
                }
            }
        }
    }

    private func navigateToContextAfterPlayerClose() {
        // Navigate to the context where the video was playing from
        switch settingsStore.lastContextType {
        case "liked":
            selectedTab = .playlists
            // Small delay to ensure tab switch completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigateToLiked = true
            }
        case "playlist":
            if let playlistId = UUID(uuidString: settingsStore.lastPlaylistId) {
                selectedTab = .playlists
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigateToPlaylistId = playlistId
                }
            }
        default:
            // "all" context - stay on library tab
            selectedTab = .library
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
