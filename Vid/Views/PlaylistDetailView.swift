import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @EnvironmentObject var playerVM: PlayerViewModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var focusedElement: AppFocus?

    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showThumbnails = true
    @State private var showAddVideos = false

    enum SortOption {
        case name, duration, recent, size, mostWatched
    }

    private func defaultOrder(for option: SortOption) -> Bool {
        switch option {
        case .name:
            return true
        case .duration, .recent, .size, .mostWatched:
            return false
        }
    }

    var livePlaylist: Playlist {
        playlistManager.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    var resolvedVideos: [Video] {
        livePlaylist.videoIds.compactMap { id in
            videoManager.videos.first(where: { $0.id == id })
        }
    }

    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return resolvedVideos
        } else {
            return resolvedVideos.filter { video in
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
        VStack(spacing: 0) {
            // Top Navigation Bar
            DetailNavigationBar(
                title: livePlaylist.name,
                onBack: { presentationMode.wrappedValue.dismiss() },
                trailingContent: { AnyView(trailingButtons) }
            )

            // Content
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showAddVideos) {
            AddVideosToPlaylistView(playlistId: playlist.id, videoManager: videoManager, playlistManager: playlistManager)
        }
        .onAppear {
            if focusedElement == nil {
                if let firstId = sortedVideos.first?.id {
                    focusedElement = .videoItem(firstId)
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        Group {
            if resolvedVideos.isEmpty {
                emptyStateView
            } else {
                videoListContent
            }
        }
    }

    @ViewBuilder
    private var videoListContent: some View {
        VStack(spacing: 0) {
            if showSearch {
                searchBar
            }

            VideoListView(
                videos: sortedVideos,
                showThumbnails: showThumbnails,
                focusedElement: $focusedElement,
                onDelete: { offsets in deleteVideo(at: offsets) },
                onPlay: { video in
                    settings.lastContextType = "playlist"
                    settings.lastPlaylistId = playlist.id.uuidString
                    playerVM.play(video: video, from: sortedVideos, settings: settings)
                }
            )
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
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.6))
                )
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                Text("This playlist is empty")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Add videos from your library to start building this playlist.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                showAddVideos = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add Videos")
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

    @ViewBuilder
    private var trailingButtons: some View {
        HStack(spacing: 8) {
            // Plus first
            Button(action: { showAddVideos = true }) {
                Image(systemName: "plus")
                    .foregroundColor(.primary)
            }
            .buttonStyle(NavButtonStyle())

            // Then search and filter (only when there are videos)
            if !resolvedVideos.isEmpty {
                Button(action: {
                    withAnimation {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                }) {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                        .foregroundColor(.primary)
                }
                .buttonStyle(NavButtonStyle())

                Menu {
                    Section {
                        Button(action: { sortOption = .name;        sortAscending = defaultOrder(for: .name) }) { Label("Name",        systemImage: sortOption == .name ? "checkmark" : "") }
                        Button(action: { sortOption = .duration;    sortAscending = defaultOrder(for: .duration) }) { Label("Duration",    systemImage: sortOption == .duration ? "checkmark" : "") }
                        Button(action: { sortOption = .recent;      sortAscending = defaultOrder(for: .recent) }) { Label("Recent",      systemImage: sortOption == .recent ? "checkmark" : "") }
                        Button(action: { sortOption = .size;        sortAscending = defaultOrder(for: .size) }) { Label("Size",        systemImage: sortOption == .size ? "checkmark" : "") }
                        Button(action: { sortOption = .mostWatched; sortAscending = defaultOrder(for: .mostWatched) }) { Label("Most Watched", systemImage: sortOption == .mostWatched ? "checkmark" : "") }
                    }

                    Divider()

                    Section {
                        Button(action: { sortAscending = true })  { Label("Ascending",  systemImage: sortAscending ? "checkmark" : "") }
                        Button(action: { sortAscending = false }) { Label("Descending", systemImage: !sortAscending ? "checkmark" : "") }
                    }

                    Divider()

                    Button(action: { showThumbnails.toggle() }) { Label("Show Thumbnails", systemImage: showThumbnails ? "checkmark" : "") }
                } label: {
                    NavIconCircle(systemName: "ellipsis")
                }
            }
        }
    }

    func deleteVideo(at offsets: IndexSet) {
        let idsToRemove = offsets.map { sortedVideos[$0].id }
        for id in idsToRemove {
            playlistManager.removeVideo(id: id, from: playlist.id)
        }
    }
}
