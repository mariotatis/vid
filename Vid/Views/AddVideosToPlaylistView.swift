import SwiftUI

struct AddVideosToPlaylistView: View {
    let playlistId: UUID
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var playlistManager: PlaylistManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var searchText = ""
    @State private var selectedVideoIds: Set<String> = []
    
    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return videoManager.videos
        } else {
            return videoManager.videos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText)
            
            List {
                ForEach(filteredVideos) { video in
                    Button(action: {
                        toggleSelection(video)
                    }) {
                        HStack {
                            Image(systemName: selectedVideoIds.contains(video.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedVideoIds.contains(video.id) ? .blue : .gray)
                            Text(video.name)
                            Spacer()
                            Text(video.durationFormatted)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            
            Button(action: save) {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Add Videos")
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

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search", text: $text)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}
