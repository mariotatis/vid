import SwiftUI

enum PlaylistViewStyle: String, CaseIterable {
    case list = "list"
    case grid = "grid"
}

struct PlaylistsView: View {
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @AppStorage("playlistViewStyle") private var viewStyle: PlaylistViewStyle = .grid
    @FocusState private var focusedElement: AppFocus?
    @State private var isShowingLikedVideos = false

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
            Group {
                if !hasAnyContent {
                    emptyStateView
                } else if viewStyle == .list {
                    playlistListView
                } else {
                    playlistGridView
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        Button(action: {
                            newPlaylistName = ""
                            showCreatePlaylist = true
                        }) {
                            Image(systemName: "plus")
                                .foregroundColor(Color.primary)
                        }
                        .buttonStyle(VidButtonStyle())
                        .focused($focusedElement, equals: .search)

                        if hasAnyContent {
                            Menu {
                                Button(action: { viewStyle = .list }) {
                                    Label("List View", systemImage: viewStyle == .list ? "checkmark" : "")
                                }
                                Button(action: { viewStyle = .grid }) {
                                    Label("Grid View", systemImage: viewStyle == .grid ? "checkmark" : "")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(Color.primary)
                            }
                            .buttonStyle(VidButtonStyle())
                        }
                    }
                }
            }
            .alert("New Playlist", isPresented: $showCreatePlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    if !newPlaylistName.isEmpty {
                        playlistManager.createPlaylist(name: newPlaylistName)
                    }
                }
            }
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
    }

    private var playlistListView: some View {
        List {
            // Liked playlist at the top
            if shouldShowLikedPlaylist {
                NavigationLink(destination: LikedVideosView(videoManager: videoManager, settings: settings)
                    .onAppear { isShowingLikedVideos = true }
                    .onDisappear { isShowingLikedVideos = false }
                ) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Liked")
                                .font(.headline)
                            Text("\(likedVideoCount) videos")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .vidFocusHighlight()
                }
                .focused($focusedElement, equals: .likedPlaylist)
            }

            ForEach(playlistManager.playlists) { playlist in
                NavigationLink(destination: PlaylistDetailView(playlist: playlist, playlistManager: playlistManager, videoManager: videoManager, settings: settings)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.headline)
                        Text("\(playlist.videoIds.count) videos")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .vidFocusHighlight()
                }
                .focused($focusedElement, equals: .playlistItem(playlist.id))
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
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Icon with shadow
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 120, height: 120)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(Color.gray.opacity(0.6))
                        HStack(spacing: 4) {
                            ForEach(0..<3) { _ in
                                Circle()
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                )
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
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

            // Action button
            Button(action: {
                newPlaylistName = ""
                showCreatePlaylist = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create Playlist")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(white: 0.25))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
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
