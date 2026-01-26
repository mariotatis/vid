import SwiftUI

struct LikedVideosView: View {
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var focusedElement: AppFocus?

    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showThumbnails = true

    enum SortOption {
        case name, duration, recent, size, mostWatched
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
        ZStack(alignment: .top) {
            // Content
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top Navigation Bar
            VStack(spacing: 0) {
                DetailNavigationBar(
                    title: "Liked",
                    onBack: { presentationMode.wrappedValue.dismiss() },
                    trailingContent: { AnyView(trailingButtons) }
                )

                Spacer()
            }
        }
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
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
            if likedVideos.isEmpty {
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
                    .padding(.top, TOP_NAV_CONTENT_INSET)
            }

            VideoListView(
                videos: sortedVideos,
                showThumbnails: showThumbnails,
                focusedElement: $focusedElement,
                onDelete: { offsets in unlikeVideo(at: offsets) },
                onPlay: { video in
                    settings.lastContextType = "liked"
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
    }

    @ViewBuilder
    private var trailingButtons: some View {
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
                        .foregroundColor(.primary)
                }
                .buttonStyle(NavButtonStyle())

                Menu {
                    Section {
                        Button(action: { sortOption = .name }) {
                            Label("Name", systemImage: sortOption == .name ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .duration }) {
                            Label("Duration", systemImage: sortOption == .duration ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .recent }) {
                            Label("Recent", systemImage: sortOption == .recent ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .size }) {
                            Label("Size", systemImage: sortOption == .size ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .mostWatched }) {
                            Label("Most Watched", systemImage: sortOption == .mostWatched ? "checkmark" : "")
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.primary)
                }
                .buttonStyle(NavButtonStyle())
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
