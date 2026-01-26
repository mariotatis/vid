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
        VStack(spacing: 24) {
            // Icon with shadow
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "music.note.list")
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
                Text("No playlists yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Create playlists to organize your videos by mood, genre, or any way you like.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Note: The create button is now in the top navigation bar
            Text("Tap + in the top bar to create a playlist")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LikedPlaylistPreviewCell: View {
    let likedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Heart icon instead of 4-square grid
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: 44))
                        .foregroundColor(Color.gray.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Liked")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text("\(likedCount) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PlaylistPreviewCell: View {
    let playlist: Playlist
    @ObservedObject var videoManager: VideoManager

    private var resolvedVideos: [Video] {
        playlist.videoIds.compactMap { id in
            videoManager.videos.first(where: { $0.id == id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 2x2 grid of thumbnails
            GeometryReader { geometry in
                let cellSize = geometry.size.width / 2

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        thumbnailCell(index: 0, size: cellSize)
                        thumbnailCell(index: 1, size: cellSize)
                    }
                    HStack(spacing: 0) {
                        thumbnailCell(index: 2, size: cellSize)
                        thumbnailCell(index: 3, size: cellSize)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text("\(playlist.videoIds.count) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(index: Int, size: CGFloat) -> some View {
        if index < resolvedVideos.count {
            VideoThumbnailView(videoURL: resolvedVideos[index].url, contentMode: .fill, width: size, height: size)
                .frame(width: size, height: size)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "video.fill")
                        .foregroundColor(.gray.opacity(0.5))
                        .font(.system(size: size * 0.3))
                )
        }
    }
}
