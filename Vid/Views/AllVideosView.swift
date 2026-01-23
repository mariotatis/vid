import SwiftUI
import UniformTypeIdentifiers


struct AllVideosView: View {
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var playerVM: PlayerViewModel
    
    @State private var showFileImporter = false
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showThumbnails = true
    @FocusState private var focusedElement: AppFocus?

    enum SortOption {
        case name, duration, recent
    }
    
    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return videoManager.videos
        } else {
            return videoManager.videos.filter { video in
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
        NavigationView {
            Group {
                if videoManager.isLoading {
                    ProgressView("Loading videos...")
                } else if videoManager.videos.isEmpty {
                    VStack {
                        Text("No videos found.")
                        Text("Add videos to the 'Vid' folder in Files app.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    VideoListView(videos: sortedVideos, showThumbnails: showThumbnails, focusedElement: $focusedElement, onDelete: { offsets in deleteVideo(at: offsets) }, onPlay: { video in
                        settings.lastContextType = "all"
                        settings.lastPlaylistId = ""
                        playerVM.play(video: video, from: sortedVideos, settings: settings)
                    })
                }
            }
            .navigationTitle("Library")
            .if(showSearch) { view in
                view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search videos")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Button(action: {
                            print("Vid: Plus button tapped")
                            showFileImporter = true
                        }) {
                            Image(systemName: "plus")
                                .foregroundColor(Color.primary)
                        }
                        .buttonStyle(VidButtonStyle())
                        .focused($focusedElement, equals: .search)

                        Button(action: {
                            Task {
                                await videoManager.loadVideosAsync()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Color.primary)
                        }
                        .buttonStyle(VidButtonStyle())
                        .focused($focusedElement, equals: .filter)
                    }
                }
                
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

                            Divider()

                            Button(action: { showThumbnails.toggle() }) {
                                Label("Show Thumbnails", systemImage: showThumbnails ? "checkmark" : "")
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
        .navigationViewStyle(.stack)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                print("Vid: Files imported: \(urls)")
                videoManager.importFiles(urls)
            case .failure(let error):
                print("Vid: Error importing files: \(error.localizedDescription)")
            }
        }
        .onAppear {
            if videoManager.videos.isEmpty {
                videoManager.loadVideos()
            }
            // Set initial focus
            if focusedElement == nil {
                if let firstId = sortedVideos.first?.id {
                    focusedElement = .videoItem(firstId)
                }
            }
        }
    }
    
    func deleteVideo(at offsets: IndexSet) {
        // Map offsets to actual videos first (since we're working with a sorted list)
        let videosToRemove = offsets.map { sortedVideos[$0] }

        for video in videosToRemove {
            // Delete the file from disk
            do {
                try FileManager.default.removeItem(at: video.url)
                print("Successfully deleted file: \(video.url.lastPathComponent)")
            } catch {
                print("Failed to delete file: \(error.localizedDescription)")
            }

            // Remove from the in-memory array
            if let index = videoManager.videos.firstIndex(of: video) {
                videoManager.videos.remove(at: index)
            }
        }

        // Save updated videos list to disk
        videoManager.saveVideosToDisk()
    }
}
