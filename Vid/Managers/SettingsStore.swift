import Foundation
import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

class SettingsStore: ObservableObject {
    @AppStorage("shuffleMode") var isShuffleOn: Bool = false
    @Published var eqValues: [Double] = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5] // Local state (Double for easier storage/compatibility)
    
    init() {}
}
