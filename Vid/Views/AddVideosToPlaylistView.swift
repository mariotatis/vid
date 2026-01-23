import SwiftUI

struct AddVideosToPlaylistView: View {
    let playlistId: UUID
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var playlistManager: PlaylistManager
    @Environment(\.presentationMode) var presentationMode

    @State private var searchText = ""
    @State private var selectedVideoIds: Set<String> = []
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var showSearch = false
    @FocusState private var focusedElement: AppFocus?

    enum SortOption {
        case name, duration, recent
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
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
                                Text(video.durationFormatted)
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

            Button(action: save) {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(VidButtonStyle())
            .padding()
            .focused($focusedElement, equals: .eqReset)
        }
        .navigationTitle("Add Videos")
        .if(showSearch) { view in
            view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search videos")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color.primary)
                            .vidFocusHighlight()
                    }
                    .focused($focusedElement, equals: .sort)
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
        presentationMode.wrappedValue.dismiss()
    }
}
