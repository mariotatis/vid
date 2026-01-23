import Foundation
import AVFoundation

struct Video: Identifiable, Codable, Equatable, Hashable {
    var id: String { url.absoluteString }
    let name: String
    let url: URL
    let duration: TimeInterval
    let dateAdded: Date

    var durationFormatted: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}
