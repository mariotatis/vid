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

    var sortedVideos: [Video] {
        videoManager.videos
            .filtered(by: searchText)
            .sorted(by: sortOption, ascending: sortAscending)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top Navigation Bar
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

                // Content area
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
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
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
                SearchBarView(searchText: $searchText)
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
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "play.rectangle.on.rectangle",
            title: "Your library is quiet",
            message: "Import your favorite movies and clips to watch them offline anytime, anywhere.\n\nTap + in the top bar to import videos"
        )
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
