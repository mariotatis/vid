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
    
    init() {
        loadEQ()
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
}
