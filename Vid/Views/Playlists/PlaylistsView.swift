import SwiftUI

enum PlaylistViewStyle: String, CaseIterable {
    case list = "list"
    case grid = "grid"
}

// Local constants for PlaylistsView
private let PLAYLIST_ROW_VERTICAL_PADDING: CGFloat = 12
private let PLAYLIST_ROW_HORIZONTAL_INSET: CGFloat = 16

struct PlaylistsView: View {
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore

    @Binding var selectedTab: NavigationTab
    @Binding var navigateToPlaylistId: UUID?
    @Binding var navigateToLiked: Bool

    var onAddVideo: (() -> Void)?
    var onAddPlaylist: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var hasPlaylistContent: Bool = false
    var sortMenuContent: (() -> AnyView)?
    var viewStyleMenuContent: (() -> AnyView)?

    @AppStorage("playlistViewStyle") private var viewStyle: PlaylistViewStyle = .grid
    @FocusState private var focusedElement: AppFocus?
    @State private var isShowingLikedVideos = false
    @State private var activeLikedNavigation = false
    @State private var activePlaylistNavigation: UUID?

    private var hasLikedVideos: Bool {
        !settings.likedVideoIds.isEmpty
    }

    private var shouldShowLikedPlaylist: Bool {
        hasLikedVideos || isShowingLikedVideos
    }

    private var likedVideoCount: Int {
        settings.likedVideoIds.count
    }

    private var hasAnyContent: Bool {
        shouldShowLikedPlaylist || !playlistManager.playlists.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Hidden NavigationLinks for programmatic navigation
                NavigationLink(
                    destination: LikedVideosView(videoManager: videoManager, settings: settings)
                        .onAppear { isShowingLikedVideos = true }
                        .onDisappear { isShowingLikedVideos = false },
                    isActive: $activeLikedNavigation
                ) {
                    EmptyView()
                }
                .hidden()

                if let playlist = playlistManager.playlists.first(where: { $0.id == activePlaylistNavigation }) {
                    NavigationLink(
                        destination: PlaylistDetailView(playlist: playlist, playlistManager: playlistManager, videoManager: videoManager, settings: settings),
                        isActive: Binding(
                            get: { activePlaylistNavigation != nil },
                            set: { if !$0 { activePlaylistNavigation = nil } }
                        )
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }

                VStack(spacing: 0) {
                    // Top Navigation Bar
                    TopNavigationBar(
                        selectedTab: $selectedTab,
                        onAddVideo: onAddVideo,
                        onToggleSearch: nil,
                        showingSearch: false,
                        videosExist: false,
                        onAddPlaylist: onAddPlaylist,
                        hasPlaylistContent: hasPlaylistContent,
                        onOpenSettings: onOpenSettings,
                        sortMenuContent: sortMenuContent,
                        viewStyleMenuContent: viewStyleMenuContent
                    )

                    // Content area
                    Group {
                        if !hasAnyContent {
                            emptyStateView
                        } else if viewStyle == .list {
                            playlistListView
                        } else {
                            playlistGridView
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if focusedElement == nil {
                if shouldShowLikedPlaylist {
                    focusedElement = .likedPlaylist
                } else if let firstId = playlistManager.playlists.first?.id {
                    focusedElement = .playlistItem(firstId)
                }
            }
        }
        .onChange(of: navigateToLiked) { shouldNavigate in
            if shouldNavigate {
                activeLikedNavigation = true
                navigateToLiked = false
            }
        }
        .onChange(of: navigateToPlaylistId) { playlistId in
            if let id = playlistId {
                activePlaylistNavigation = id
                navigateToPlaylistId = nil
            }
        }
    }

    private var playlistListView: some View {
        List {
            // Liked playlist at the top
            if shouldShowLikedPlaylist {
                ZStack {
                    NavigationLink(destination: LikedVideosView(videoManager: videoManager, settings: settings)
                        .onAppear { isShowingLikedVideos = true }
                        .onDisappear { isShowingLikedVideos = false }
                    ) {
                        EmptyView()
                    }
                    .opacity(0)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Liked")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text("\(likedVideoCount) videos")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, PLAYLIST_ROW_VERTICAL_PADDING)
                    .vidFocusHighlight()
                }
                .focused($focusedElement, equals: .likedPlaylist)
                .listRowInsets(EdgeInsets(top: 0, leading: PLAYLIST_ROW_HORIZONTAL_INSET, bottom: 0, trailing: PLAYLIST_ROW_HORIZONTAL_INSET))
                .listRowSeparatorTint(Color.gray.opacity(0.3))
            }

            ForEach(playlistManager.playlists) { playlist in
                ZStack {
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist, playlistManager: playlistManager, videoManager: videoManager, settings: settings)) {
                        EmptyView()
                    }
                    .opacity(0)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text("\(playlist.videoIds.count) videos")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, PLAYLIST_ROW_VERTICAL_PADDING)
                    .vidFocusHighlight()
                }
                .focused($focusedElement, equals: .playlistItem(playlist.id))
                .listRowInsets(EdgeInsets(top: 0, leading: PLAYLIST_ROW_HORIZONTAL_INSET, bottom: 0, trailing: PLAYLIST_ROW_HORIZONTAL_INSET))
                .listRowSeparatorTint(Color.gray.opacity(0.3))
            }
            .onDelete { indexSet in
                playlistManager.deletePlaylist(at: indexSet)
            }
        }
        .listStyle(.plain)
    }

    private var playlistGridView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                // Liked playlist at the top
                if shouldShowLikedPlaylist {
                    NavigationLink(destination: LikedVideosView(videoManager: videoManager, settings: settings)
                        .onAppear { isShowingLikedVideos = true }
                        .onDisappear { isShowingLikedVideos = false }
                    ) {
                        LikedPlaylistPreviewCell(likedCount: likedVideoCount)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedElement, equals: .likedPlaylist)
                }

                ForEach(playlistManager.playlists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist, playlistManager: playlistManager, videoManager: videoManager, settings: settings)) {
                        PlaylistPreviewCell(
                            playlist: playlist,
                            videoManager: videoManager
                        )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedElement, equals: .playlistItem(playlist.id))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "music.note.list",
            title: "No playlists yet",
            message: "Create playlists to organize your videos by mood, genre, or any way you like.\n\nTap + in the top bar to create a playlist"
        )
    }
}
