import SwiftUI
import AVKit

enum AspectRatioMode: String, CaseIterable {
    case `default` = "Default"
    case fill = "Fill"
    case ratio4_3 = "4:3"
    case ratio5_4 = "5:4"
    case ratio16_9 = "16:9"
    case ratio16_10 = "16:10"

    var gravity: AVLayerVideoGravity {
        switch self {
        case .default: return .resizeAspect
        case .fill: return .resizeAspectFill
        default: return .resize // Stretch
        }
    }

    var ratioValue: CGFloat? {
        switch self {
        case .ratio4_3: return 4/3
        case .ratio5_4: return 5/4
        case .ratio16_9: return 16/9
        case .ratio16_10: return 16/10
        default: return nil
        }
    }
}
