import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var playlistManager: PlaylistManager
    @ObservedObject var videoManager: VideoManager
    @ObservedObject var settings: SettingsStore
    
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @FocusState private var focusedElement: AppFocus?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(playlistManager.playlists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist, playlistManager: playlistManager, videoManager: videoManager, settings: settings)) {
                        Text(playlist.name)
                            .font(.headline)
                            .vidFocusHighlight()
                    }
                    .focused($focusedElement, equals: .playlistItem(playlist.id))
                }
                .onDelete { indexSet in
                    playlistManager.deletePlaylist(at: indexSet)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        newPlaylistName = ""
                        showCreatePlaylist = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(VidButtonStyle())
                    .focused($focusedElement, equals: .search) // Reusing search context for top-bar plus
                }
            }
            .alert("New Playlist", isPresented: $showCreatePlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    if !newPlaylistName.isEmpty {
                        playlistManager.createPlaylist(name: newPlaylistName)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if focusedElement == nil {
                if let firstId = playlistManager.playlists.first?.id {
                    focusedElement = .playlistItem(firstId)
                }
            }
        }
    }
}
