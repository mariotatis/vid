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
    @FocusState private var focusedElement: AppFocus?
    
    enum SortOption {
        case name, duration
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
                    VideoListView(videos: sortedVideos, focusedElement: $focusedElement, onDelete: { offsets in deleteVideo(at: offsets) }, onPlay: { video in
                        settings.lastContextType = "all"
                        settings.lastPlaylistId = ""
                        playerVM.play(video: video, from: sortedVideos, settings: settings)
                    })
                }
            }
            .navigationTitle("All Videos")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search videos")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 20) {
                        Button(action: {
                            print("Vid: Plus button tapped")
                            showFileImporter = true
                        }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(VidButtonStyle())
                        .focused($focusedElement, equals: .search) // Grouping under search for simplicity or define .plus
                        
                        Button(action: {
                            Task {
                                await videoManager.loadVideosAsync()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(VidButtonStyle())
                        .focused($focusedElement, equals: .filter) // Simplified mapping
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            Text("Name").tag(SortOption.name)
                            Text("Duration").tag(SortOption.duration)
                        }
                        
                        Divider()
                        
                        Button(action: { sortAscending.toggle() }) {
                            Label(sortAscending ? "Ascending" : "Descending", systemImage: sortAscending ? "arrow.up" : "arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .vidFocusHighlight()
                    }
                    .focused($focusedElement, equals: .sort)
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
        // Since we are displaying a sorted list, we need to find the actual items to delete.
        // But for simplicity in this file-based app, we aren't deleting files from disk usually, just from the list?
        // User said: "I can swipe left to remove a video". Usually implies removing from the list.
        // But if it's "All Videos" reflecting a folder, deleting from list implies checking if we should delete file.
        // Use safest approach: Just remove from the in-memory array for now, or ask user?
        // Let's assume removing from the VIEW, but since it's "All" which reflects a folder, maybe we shouldn't delete files.
        // Re-reading requirements: "All will list all videos... I can swipe left to remove a video".
        // I'll implement removing from the `videoManager.videos` array. It will reappear on reload if file exists.
        // Actually, to make it persist removal without deleting file, we'd need a blacklist.
        // For now, I will just remove from the `videoManager` array in memory.
        
        // Wait, because we are sorting, we map offsets to IDs first.
        let videosToRemove = offsets.map { sortedVideos[$0] }
        for video in videosToRemove {
            if let index = videoManager.videos.firstIndex(of: video) {
                videoManager.videos.remove(at: index)
            }
        }
    }
}
