import SwiftUI
import UniformTypeIdentifiers


struct AllVideosView: View {
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject var playerVM: PlayerViewModel
    @ObservedObject var playlistManager = PlaylistManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showFileImporter = false
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showThumbnails = true
    @FocusState private var focusedElement: AppFocus?

    enum SortOption {
        case name, duration, recent, size
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
            case .size:
                return sortAscending ? v1.fileSize < v2.fileSize : v1.fileSize > v2.fileSize
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if videoManager.isLoading {
                    ProgressView("Loading videos...")
                } else if videoManager.videos.isEmpty {
                    VStack(spacing: 24) {
                        // Icon with shadow
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "play.rectangle.on.rectangle")
                                        .font(.system(size: 44, weight: .medium))
                                        .foregroundColor(Color.gray.opacity(0.6))
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)

                            // Plus badge
                            Circle()
                                .fill(Color(UIColor.systemBackground))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(Color.gray.opacity(0.7))
                                )
                                .offset(x: 8, y: 8)
                        }
                        .padding(.bottom, 8)

                        // Text content
                        VStack(spacing: 12) {
                            Text("Your library is quiet")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("Import your favorite movies and clips to watch them offline anytime, anywhere.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }

                        // Action button
                        Button(action: {
                            showFileImporter = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Import Videos")
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
                    Button(action: {
                        print("Vid: Plus button tapped")
                        showFileImporter = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(Color.primary)
                    }
                    .buttonStyle(VidButtonStyle())
                    .focused($focusedElement, equals: .search)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !videoManager.videos.isEmpty {
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
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                videoManager.loadVideos()
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

            // Remove from all playlists
            for playlist in playlistManager.playlists {
                playlistManager.removeVideo(id: video.id, from: playlist.id)
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
