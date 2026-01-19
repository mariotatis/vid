import SwiftUI
import AVKit

struct CustomVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false // Hide native controls
        controller.videoGravity = videoGravity
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player != player {
            uiViewController.player = player
        }
        if uiViewController.videoGravity != videoGravity {
            uiViewController.videoGravity = videoGravity
        }
    }
}
