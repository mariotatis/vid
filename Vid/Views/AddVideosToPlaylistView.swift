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

    enum SortOption {
        case name, duration, recent, size
    }

    var currentPlaylist: Playlist? {
        playlistManager.playlists.first(where: { $0.id == playlistId })
    }

    var availableVideos: [Video] {
        guard let playlist = currentPlaylist else { return videoManager.videos }
        return videoManager.videos.filter { !playlist.videoIds.contains($0.id) }
    }

    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return availableVideos
        } else {
            return availableVideos.filter { video in
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
            case .size:
                return sortAscending ? v1.fileSize < v2.fileSize : v1.fileSize > v2.fileSize
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                if availableVideos.isEmpty {
                    // Empty state
                    VStack(spacing: 24) {
                        // Icon with shadow
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: videoManager.videos.isEmpty ? "film.stack" : "checkmark.circle")
                                    .font(.system(size: 44, weight: .medium))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                            .padding(.bottom, 8)

                        // Text content
                        VStack(spacing: 12) {
                            Text(videoManager.videos.isEmpty ? "No videos in library" : "All videos added")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text(videoManager.videos.isEmpty
                                ? "Import videos to your library first, then add them to this playlist."
                                : "All your videos are already in this playlist.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }

                        // Close button
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Close")
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
                                }
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

                                    Button(action: {
                                        sortOption = .size
                                    }) {
                                        Label("Size", systemImage: sortOption == .size ? "checkmark" : "")
                                    }
                                }

                                Divider()

                                Button(action: { sortAscending.toggle() }) {
                                    Label(sortAscending ? "Ascending" : "Descending", systemImage: sortAscending ? "arrow.up" : "arrow.down")
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
