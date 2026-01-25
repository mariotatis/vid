import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @EnvironmentObject var playerVM: PlayerViewModel
    @ObservedObject var settings: SettingsStore
    @FocusState private var focusedElement: AppFocus?

    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showThumbnails = false
    @State private var showAddVideos = false

    enum SortOption {
        case name, duration, recent
    }

    // We need to resolve videoIds to Video objects.
    // Since Playlist is a Struct (value type), and we want to know when it updates (though the list passed in is static value).
    // We rely on `playlistManager` updates. We need to find the current playlist in the manager.

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
                return sortAscending ? v1.dateAdded < v2.dateAdded : v1.dateAdded > v2.dateAdded
            }
        }
    }
    
    var body: some View {
        Group {
            if resolvedVideos.isEmpty {
                VStack(spacing: 24) {
                    // Icon with shadow
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

                    // Text content
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

                    // Action button
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
            } else {
                VideoListView(videos: sortedVideos, showThumbnails: showThumbnails, focusedElement: $focusedElement, onDelete: { offsets in deleteVideo(at: offsets) }, onPlay: { video in
                    settings.lastContextType = "playlist"
                    settings.lastPlaylistId = playlist.id.uuidString
                    playerVM.play(video: video, from: sortedVideos, settings: settings)
                })
            }
        }
        .navigationTitle(livePlaylist.name)
        .if(showSearch) { view in
            view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search videos")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if !resolvedVideos.isEmpty {
                        Button(action: {
                            withAnimation {
                                showSearch.toggle()
                                if !showSearch {
                                    searchText = ""
                                }
                            }
                        }) {
                            Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                                .foregroundColor(Color.primary)
                        }
                        .buttonStyle(VidButtonStyle())

                        Menu {
                        Section {
                            Button(action: {
                                sortOption = .name
                            }) {
                                Label("Name", systemImage: sortOption == .name ? "checkmark" : "")
                            }

                            Button(action: {
                                sortOption = .duration
                            }) {
                                Label("Duration", systemImage: sortOption == .duration ? "checkmark" : "")
                            }

                            Button(action: {
                                sortOption = .recent
                            }) {
                                Label("Recent", systemImage: sortOption == .recent ? "checkmark" : "")
                            }
                        }

                        Divider()

                        Button(action: { sortAscending.toggle() }) {
                            Label(sortAscending ? "Ascending" : "Descending", systemImage: sortAscending ? "arrow.up" : "arrow.down")
                        }

                        Divider()

                        Button(action: { showThumbnails.toggle() }) {
                            Label("Show Thumbnails", systemImage: showThumbnails ? "checkmark" : "")
                        }

                        Divider()

                        Button(action: { settings.autoplayOnAppOpen.toggle() }) {
                            Label("Autoplay on App Open", systemImage: settings.autoplayOnAppOpen ? "checkmark" : "")
                        }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(Color.primary)
                                .vidFocusHighlight()
                        }
                        .focused($focusedElement, equals: .sort)
                    }

                    Button(action: {
                        showAddVideos = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(Color.primary)
                            .vidFocusHighlight()
                    }
                    .buttonStyle(VidButtonStyle())
                    .focused($focusedElement, equals: .search)
                }
            }
        }
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
    
    func deleteVideo(at offsets: IndexSet) {
        let idsToRemove = offsets.map { sortedVideos[$0].id }
        for id in idsToRemove {
            playlistManager.removeVideo(id: id, from: playlist.id)
        }
    }
}
