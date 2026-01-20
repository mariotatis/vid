import Foundation
import SwiftUI

#if canImport(AppIntents)
import AppIntents

// MARK: - Entities

@available(iOS 16.0, *)
struct PlaylistEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static var defaultQuery = PlaylistQuery()
    
    let id: UUID
    let name: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 16.0, *)
struct PlaylistQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlaylistEntity] {
        PlaylistManager.shared.playlists
            .filter { identifiers.contains($0.id) }
            .map { PlaylistEntity(id: $0.id, name: $0.name) }
    }
    
    func suggestedEntities() async throws -> [PlaylistEntity] {
        PlaylistManager.shared.playlists
            .map { PlaylistEntity(id: $0.id, name: $0.name) }
    }
    
    func entities(matching string: String) async throws -> [PlaylistEntity] {
        PlaylistManager.shared.playlists
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { PlaylistEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - App Intents

@available(iOS 16.0, *)
struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Plays a specific playlist.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = PlaylistManager.shared
        let videoManager = VideoManager.shared
        let playerVM = PlayerViewModel.shared
        let settings = SettingsStore.shared

        if let foundPlaylist = manager.playlists.first(where: { $0.id == playlist.id }) {
            let videos = foundPlaylist.videoIds.compactMap { id in
                videoManager.videos.first(where: { $0.id == id })
            }
            
            if let first = videos.first {
                playerVM.play(video: first, from: videos, settings: settings)
                return .result(value: "Playing playlist \(foundPlaylist.name)")
            } else {
                return .result(value: "The playlist \(foundPlaylist.name) is empty.")
            }
        }
        
        return .result(value: "I couldn't find that playlist.")
    }
}

@available(iOS 16.0, *)
struct SearchAndPlayVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "Search and Play"
    static var description = IntentDescription("Searches for a video and plays it.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Video Name")
    var searchQuery: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let videoManager = VideoManager.shared
        let playerVM = PlayerViewModel.shared
        let settings = SettingsStore.shared

        let searchResults = videoManager.videos.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        
        if let first = searchResults.first {
            playerVM.play(video: first, from: videoManager.videos, settings: settings)
            return .result(value: "Playing \(first.name)")
        }
        
        return .result(value: "I couldn't find any videos for \(searchQuery).")
    }
}

// MARK: - App Shortcuts

@available(iOS 16.0, *)
struct VidShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play a playlist on \(.applicationName)",
                "Start playing a playlist on \(.applicationName)",
                "Reproducir una lista en \(.applicationName)",
                "Tocar una lista en \(.applicationName)",
                "Play playlist \(\.$playlist) on \(.applicationName)",
                "Reproducir la lista \(\.$playlist) en \(.applicationName)"
            ],
            shortTitle: "Play Playlist",
            systemImageName: "play.circle"
        )
        
        AppShortcut(
            intent: SearchAndPlayVideoIntent(),
            phrases: [
                "Search a video on \(.applicationName)",
                "Play a video on \(.applicationName)",
                "Buscar videos en \(.applicationName)",
                "Reproducir un video en \(.applicationName)"
            ],
            shortTitle: "Search and Play",
            systemImageName: "magnifyingglass"
        )
    }
    
    // This property allows localizing the shortcuts names and phrases more effectively in XCART/Indexing
    static var shortcutTileColor: ShortcutTileColor = .blue
}
#endif
