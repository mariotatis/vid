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

    var likedVideos: [Video] {
        videoManager.videos.filter { settings.likedVideoIds.contains($0.id) }
    }

    var sortedVideos: [Video] {
        likedVideos
            .filtered(by: searchText)
            .sorted(by: sortOption, ascending: sortAscending)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            DetailNavigationBar(
                title: "Liked",
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
                SearchBarView(searchText: $searchText)
            }

            VideoListView(
                videos: sortedVideos,
                showThumbnails: settings.showThumbnails,
                focusedElement: $focusedElement,
                onDelete: { offsets in unlikeVideo(at: offsets) },
                onPlay: { video in
                    settings.lastContextType = "liked"
                    settings.lastPlaylistId = ""
                    playerVM.play(video: video, from: sortedVideos, settings: settings)
                }
            )
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "heart.slash",
            title: "No liked videos",
            message: "Videos you like will appear here. Tap the heart icon in the player to like a video.",
            showBadge: false
        )
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
                        Button(action: { sortOption = .name; sortAscending = SortOption.name.defaultAscending }) {
                            Label("Name", systemImage: sortOption == .name ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .duration; sortAscending = SortOption.duration.defaultAscending }) {
                            Label("Duration", systemImage: sortOption == .duration ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .recent; sortAscending = SortOption.recent.defaultAscending }) {
                            Label("Recent", systemImage: sortOption == .recent ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .size; sortAscending = SortOption.size.defaultAscending }) {
                            Label("Size", systemImage: sortOption == .size ? "checkmark" : "")
                        }

                        Button(action: { sortOption = .mostWatched; sortAscending = SortOption.mostWatched.defaultAscending }) {
                            Label("Most Watched", systemImage: sortOption == .mostWatched ? "checkmark" : "")
                        }
                    }

                    Divider()

                    Button(action: { sortAscending.toggle() }) {
                        Label(sortAscending ? "Ascending" : "Descending", systemImage: sortAscending ? "arrow.up" : "arrow.down")
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
