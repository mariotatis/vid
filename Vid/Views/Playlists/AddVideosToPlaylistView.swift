import SwiftUI

struct AddVideosToPlaylistView: View {
    let playlistId: UUID
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var playlistManager: PlaylistManager
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var selectedVideoIds: Set<String> = []
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var showSearch = false
    @FocusState private var focusedElement: AppFocus?

    var currentPlaylist: Playlist? {
        playlistManager.playlists.first(where: { $0.id == playlistId })
    }

    var availableVideos: [Video] {
        guard let playlist = currentPlaylist else { return videoManager.videos }
        return videoManager.videos.filter { !playlist.videoIds.contains($0.id) }
    }

    var sortedVideos: [Video] {
        availableVideos
            .filtered(by: searchText)
            .sorted(by: sortOption, ascending: sortAscending)
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                if availableVideos.isEmpty {
                    EmptyStateView(
                        icon: videoManager.videos.isEmpty ? "film.stack" : "checkmark.circle",
                        title: videoManager.videos.isEmpty ? "No videos in library" : "All videos added",
                        message: videoManager.videos.isEmpty
                            ? "Import videos to your library first, then add them to this playlist."
                            : "All your videos are already in this playlist.",
                        showBadge: false,
                        action: { dismiss() },
                        actionTitle: "Close",
                        actionIcon: "xmark.circle"
                    )
                } else {
                    List {
                        ForEach(sortedVideos) { video in
                            Button(action: {
                                toggleSelection(video)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedVideoIds.contains(video.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedVideoIds.contains(video.id) ? .blue : .gray)
                                        .font(.system(size: 22))

                                    VStack(alignment: .leading) {
                                        Text(video.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .foregroundColor(.primary)
                                        Text("\(video.durationFormatted) - \(video.fileSizeFormatted)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if !video.isWatched {
                                        Text("NEW")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .cornerRadius(4)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .background(focusedElement == .videoItem(video.id) ? Color.blue.opacity(0.15) : Color.clear)
                                .cornerRadius(8)
                                .vidFocusHighlight()
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparatorTint(Color.gray.opacity(0.3))
                            .focused($focusedElement, equals: .videoItem(video.id))
                        }
                    }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 100)
                }

                    // Fixed bottom card
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Selected")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(selectedVideoIds.count) Videos")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }

                            Spacer()

                            Button(action: save) {
                                Text("Add to Playlist")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(selectedVideoIds.isEmpty ? Color.gray : Color.blue)
                                    .cornerRadius(10)
                            }
                            .disabled(selectedVideoIds.isEmpty)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial)
                    }
                } // else
            } // ZStack
            .navigationTitle("Add Videos")
            .navigationBarTitleDisplayMode(.inline)
            .if(showSearch) { view in
                view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search videos")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Color.primary)
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(VidButtonStyle())
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !availableVideos.isEmpty {
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

                                Section {
                                    Button(action: { sortAscending = true }) {
                                        Label("Ascending", systemImage: sortAscending ? "checkmark" : "")
                                    }
                                    Button(action: { sortAscending = false }) {
                                        Label("Descending", systemImage: !sortAscending ? "checkmark" : "")
                                    }
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
        .navigationViewStyle(.stack)
    }

    func toggleSelection(_ video: Video) {
        if selectedVideoIds.contains(video.id) {
            selectedVideoIds.remove(video.id)
        } else {
            selectedVideoIds.insert(video.id)
        }
    }

    func save() {
        let videosToAdd = videoManager.videos.filter { selectedVideoIds.contains($0.id) }
        playlistManager.addVideos(videosToAdd, to: playlistId)
        dismiss()
    }
}
