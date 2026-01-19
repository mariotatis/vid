import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var videoIds: [String] // Stores Video.id (url absoluteString)
}
