import SwiftUI
import UniformTypeIdentifiers


struct AllVideosView: View {
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var playerVM: PlayerViewModel
    @ObservedObject var playlistManager = PlaylistManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @Binding var selectedTab: NavigationTab
    @Binding var showSearch: Bool

    var onAddVideo: (() -> Void)?
    var onAddPlaylist: (() -> Void)?
    var hasPlaylistContent: Bool = false
    var sortMenuContent: (() -> AnyView)?
    var viewStyleMenuContent: (() -> AnyView)?

    @AppStorage("librarySortOption") private var sortOptionRaw: String = "name"
    @AppStorage("librarySortAscending") private var sortAscending: Bool = true
    @AppStorage("libraryShowThumbnails") private var showThumbnails: Bool = true

    @State private var searchText = ""
    @FocusState private var focusedElement: AppFocus?

    private var sortOption: SortOption {
        SortOption(rawValue: sortOptionRaw) ?? .name
    }

    enum SortOption: String {
        case name, duration, recent, size, mostWatched
    }

    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return videoManager.videos
        } else {
            return videoManager.videos.filter { video in
                let name = video.name.folding(options: .diacriticInsensitive, locale: .current)
                let query = searchText.folding(options: .diacriticInsensitive, locale: .current)
                return name.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var sortedVideos: [Video] {
        return filteredVideos.sorted { v1, v2 in
            switch sortOption {
            case .name:
                return sortAscending ? v1.name < v2.name : v1.name > v2.name
            case .duration:
                return sortAscending ? v1.duration < v2.duration : v1.duration > v2.duration
            case .recent:
                if v1.isWatched != v2.isWatched {
                    return !v1.isWatched
                }
                return sortAscending ? v1.dateAdded < v2.dateAdded : v1.dateAdded > v2.dateAdded
            case .size:
                return sortAscending ? v1.fileSize < v2.fileSize : v1.fileSize > v2.fileSize
            case .mostWatched:
                return sortAscending ? v1.watchCount < v2.watchCount : v1.watchCount > v2.watchCount
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Content area
                NavigationView {
                    Group {
                        if videoManager.isLoading {
                            ProgressView("Loading videos...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if videoManager.videos.isEmpty {
                            emptyStateView
                        } else {
                            videoListContent
                        }
                    }
                    .navigationBarHidden(true)
                }
                .navigationViewStyle(.stack)

                // Top Navigation Bar
                VStack(spacing: 0) {
                    TopNavigationBar(
                        selectedTab: $selectedTab,
                        onAddVideo: onAddVideo,
                        onToggleSearch: {
                            withAnimation {
                                showSearch.toggle()
                            }
                        },
                        showingSearch: showSearch,
                        videosExist: !videoManager.videos.isEmpty,
                        onAddPlaylist: onAddPlaylist,
                        hasPlaylistContent: hasPlaylistContent,
                        sortMenuContent: sortMenuContent,
                        viewStyleMenuContent: viewStyleMenuContent
                    )
                    .padding(.top, geometry.safeAreaInsets.top)

                    Spacer()
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .onChange(of: showSearch) { newValue in
            if !newValue {
                searchText = ""
            }
        }
        .onAppear {
            if videoManager.videos.isEmpty {
                videoManager.loadVideos()
            }
            if focusedElement == nil {
                if let firstId = sortedVideos.first?.id {
                    focusedElement = .videoItem(firstId)
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                videoManager.loadVideos()
            }
        }
    }

    @ViewBuilder
    private var videoListContent: some View {
        VStack(spacing: 0) {
            if showSearch {
                searchBar
                    .padding(.top, TOP_NAV_CONTENT_INSET)
            }

            VideoListView(
                videos: sortedVideos,
                showThumbnails: showThumbnails,
                focusedElement: $focusedElement,
                onDelete: { offsets in deleteVideo(at: offsets) },
                onPlay: { video in
                    settings.lastContextType = "all"
                    settings.lastPlaylistId = ""
                    playerVM.play(video: video, from: sortedVideos, settings: settings)
                }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: showSearch ? 0 : TOP_NAV_CONTENT_INSET)
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search videos", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Icon with shadow
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundColor(Color.gray.opacity(0.6))
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)

                // Plus badge
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color.gray.opacity(0.7))
                    )
                    .offset(x: 8, y: 8)
            }
            .padding(.bottom, 8)

            // Text content
            VStack(spacing: 12) {
                Text("Your library is quiet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Import your favorite movies and clips to watch them offline anytime, anywhere.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Note: The import button is now in the top navigation bar
            Text("Tap + in the top bar to import videos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func deleteVideo(at offsets: IndexSet) {
        // Map offsets to actual videos first (since we're working with a sorted list)
        let videosToRemove = offsets.map { sortedVideos[$0] }

        for video in videosToRemove {
            // Delete the file from disk
            do {
                try FileManager.default.removeItem(at: video.url)
                print("Successfully deleted file: \(video.url.lastPathComponent)")
            } catch {
                print("Failed to delete file: \(error.localizedDescription)")
            }

            // Remove from all playlists
            for playlist in playlistManager.playlists {
                playlistManager.removeVideo(id: video.id, from: playlist.id)
            }

            // Remove from Liked set
            if settings.likedVideoIds.contains(video.id) {
                settings.likedVideoIds.remove(video.id)
            }

            // Remove from the in-memory array
            if let index = videoManager.videos.firstIndex(of: video) {
                videoManager.videos.remove(at: index)
            }
        }

        // Save updated videos list to disk
        videoManager.saveVideosToDisk()
    }
}
