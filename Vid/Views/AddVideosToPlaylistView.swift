import SwiftUI

struct AddVideosToPlaylistView: View {
    let playlistId: UUID
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var playlistManager: PlaylistManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var searchText = ""
    @State private var selectedVideoIds: Set<String> = []
    @FocusState private var focusedElement: AppFocus?
    
    var filteredVideos: [Video] {
        if searchText.isEmpty {
            return videoManager.videos
        } else {
            return videoManager.videos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText, focused: $focusedElement)
            
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
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(focusedElement == .videoItem(video.id) ? Color.blue.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                        .vidFocusHighlight()
                    }
                    .buttonStyle(.plain)
                    .focused($focusedElement, equals: .videoItem(video.id))
                }
            }
            
            Button(action: save) {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(VidButtonStyle())
            .padding()
            .focused($focusedElement, equals: .eqReset) // Reusing eqReset as placeholder for Save context
        }
        .navigationTitle("Add Videos")
        .onAppear {
            if focusedElement == nil {
                focusedElement = .search
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

struct SearchBar: View {
    @Binding var text: String
    var focused: FocusState<AppFocus?>.Binding
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search", text: $text)
                .focused(focused, equals: .search)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .vidFocusHighlight()
        .focused(focused, equals: .search)
    }
}
