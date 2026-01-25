import Foundation
import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @AppStorage("shuffleMode") var isShuffleOn: Bool = false
    @AppStorage("aspectRatioMode") var aspectRatioMode: AspectRatioMode = .fill
    @AppStorage("lastContextType") var lastContextType: String = "" // "all" or "playlist"
    @AppStorage("lastPlaylistId") var lastPlaylistId: String = ""
    @AppStorage("lastVideoId") var lastVideoId: String = ""
    @AppStorage("autoplayOnAppOpen") var autoplayOnAppOpen: Bool = false

    @Published var preampValue: Double = 0.5 {
        didSet {
            UserDefaults.standard.set(preampValue, forKey: "preampValue")
        }
    }

    @Published var eqValues: [Double] = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5] {
        didSet {
            saveEQ()
        }
    }

    @Published var likedVideoIds: Set<String> = [] {
        didSet {
            saveLikedVideos()
        }
    }

    init() {
        loadEQ()
        loadLikedVideos()
        if let savedPreamp = UserDefaults.standard.object(forKey: "preampValue") as? Double {
            preampValue = savedPreamp
        }
    }
    
    private func saveEQ() {
        if let data = try? JSONEncoder().encode(eqValues) {
            UserDefaults.standard.set(data, forKey: "eqValues")
        }
    }

    private func loadEQ() {
        if let data = UserDefaults.standard.data(forKey: "eqValues"),
           let decoded = try? JSONDecoder().decode([Double].self, from: data) {
            eqValues = decoded
        }
    }

    private func saveLikedVideos() {
        if let data = try? JSONEncoder().encode(Array(likedVideoIds)) {
            UserDefaults.standard.set(data, forKey: "likedVideoIds")
        }
    }

    private func loadLikedVideos() {
        if let data = UserDefaults.standard.data(forKey: "likedVideoIds"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            likedVideoIds = Set(decoded)
        }
    }

    /// Remove likes that no longer correspond to any known video IDs
    func pruneMissingLikes(validIds: Set<String>) {
        let pruned = likedVideoIds.intersection(validIds)
        if pruned != likedVideoIds {
            likedVideoIds = pruned
        }
    }

    func isVideoLiked(_ videoId: String) -> Bool {
        likedVideoIds.contains(videoId)
    }

    func toggleLike(for videoId: String) {
        if likedVideoIds.contains(videoId) {
            likedVideoIds.remove(videoId)
        } else {
            likedVideoIds.insert(videoId)
        }
    }
}
