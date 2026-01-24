import SwiftUI

enum PlaylistViewStyle: String, CaseIterable {
    case list = "list"
    case preview = "preview"
}

struct PlaylistsView: View {
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var viewStyle: PlaylistViewStyle = .list
    @FocusState private var focusedElement: AppFocus?

    var body: some View {
        NavigationView {
            Group {
                if viewStyle == .list {
                    playlistListView
                } else {
                    playlistPreviewGrid
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

                        Menu {
                            Button(action: { viewStyle = .list }) {
                                Label("List", systemImage: viewStyle == .list ? "checkmark" : "")
                            }
                            Button(action: { viewStyle = .preview }) {
                                Label("Preview", systemImage: viewStyle == .preview ? "checkmark" : "")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(Color.primary)
                        }
                        .buttonStyle(VidButtonStyle())
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
                if let firstId = playlistManager.playlists.first?.id {
                    focusedElement = .playlistItem(firstId)
                }
            }
        }
    }

    private var playlistListView: some View {
        List {
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

    private var playlistPreviewGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
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
                let cellSize = (geometry.size.width - 2) / 2

                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        thumbnailCell(index: 0, size: cellSize)
                        thumbnailCell(index: 1, size: cellSize)
                    }
                    HStack(spacing: 2) {
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
            VideoThumbnailView(videoURL: resolvedVideos[index].url)
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
