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

    var livePlaylist: Playlist {
        playlistManager.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    var resolvedVideos: [Video] {
        livePlaylist.videoIds.compactMap { id in
            videoManager.videos.first(where: { $0.id == id })
        }
    }

    var sortedVideos: [Video] {
        resolvedVideos
            .filtered(by: searchText)
            .sorted(by: sortOption, ascending: sortAscending)
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
                SearchBarView(searchText: $searchText)
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

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "text.badge.plus",
            title: "This playlist is empty",
            message: "Add videos from your library to start building this playlist.",
            showBadge: false,
            action: { showAddVideos = true },
            actionTitle: "Add Videos",
            actionIcon: "plus.circle"
        )
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
                        Button(action: { sortOption = .name;        sortAscending = SortOption.name.defaultAscending }) { Label("Name",        systemImage: sortOption == .name ? "checkmark" : "") }
                        Button(action: { sortOption = .duration;    sortAscending = SortOption.duration.defaultAscending }) { Label("Duration",    systemImage: sortOption == .duration ? "checkmark" : "") }
                        Button(action: { sortOption = .recent;      sortAscending = SortOption.recent.defaultAscending }) { Label("Recent",      systemImage: sortOption == .recent ? "checkmark" : "") }
                        Button(action: { sortOption = .size;        sortAscending = SortOption.size.defaultAscending }) { Label("Size",        systemImage: sortOption == .size ? "checkmark" : "") }
                        Button(action: { sortOption = .mostWatched; sortAscending = SortOption.mostWatched.defaultAscending }) { Label("Most Watched", systemImage: sortOption == .mostWatched ? "checkmark" : "") }
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
