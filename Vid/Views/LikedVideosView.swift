import SwiftUI

struct LikedVideosView: View {
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var playerVM: PlayerViewModel
    @FocusState private var focusedElement: AppFocus?

    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showThumbnails = false

    enum SortOption {
        case name, duration, recent
    }

    var likedVideos: [Video] {
        videoManager.videos.filter { settings.likedVideoIds.contains($0.id) }
    }

    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return likedVideos
        } else {
            return likedVideos.filter { video in
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
            if likedVideos.isEmpty {
                VStack(spacing: 24) {
                    // Icon with shadow
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "heart.slash")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundColor(Color.gray.opacity(0.6))
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .padding(.bottom, 8)

                    // Text content
                    VStack(spacing: 12) {
                        Text("No liked videos")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("Videos you like will appear here. Tap the heart icon in the player to like a video.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VideoListView(videos: sortedVideos, showThumbnails: showThumbnails, focusedElement: $focusedElement, onDelete: { offsets in unlikeVideo(at: offsets) }, onPlay: { video in
                    settings.lastContextType = "liked"
                    settings.lastPlaylistId = ""
                    playerVM.play(video: video, from: sortedVideos, settings: settings)
                })
            }
        }
        .navigationTitle("Liked")
        .if(showSearch) { view in
            view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search videos")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !likedVideos.isEmpty {
                    HStack(spacing: 8) {
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
                }
            }
        }
        .onAppear {
            if focusedElement == nil {
                if let firstId = sortedVideos.first?.id {
                    focusedElement = .videoItem(firstId)
                }
            }
        }
    }

    func unlikeVideo(at offsets: IndexSet) {
        let idsToRemove = offsets.map { sortedVideos[$0].id }
        for id in idsToRemove {
            settings.likedVideoIds.remove(id)
        }
    }
}
