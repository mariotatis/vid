import Foundation
import UIKit
import AVKit
import AVFoundation
import Combine
import MediaPlayer

class PlayerViewModel: ObservableObject {
    static let shared = PlayerViewModel()
    @Published var player: AVPlayer = AVPlayer()
    @Published var currentVideo: Video?
    @Published var isPlaying: Bool = false
    @Published var showPlayer: Bool = false
    
    // Audio Engine Components
    // Internal access for extensions
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    let eqNode = AVAudioUnitEQ(numberOfBands: 6)
    
    var queue: [Video] = []
    var originalQueue: [Video] = []
    var currentIndex: Int = 0
    var cancellables = Set<AnyCancellable>()
    var settingsCancellable: AnyCancellable?
    
    var isShuffleOn: Bool = false
    
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isSeeking = false
    
    // Audio File State
    var audioFile: AVAudioFile?
    var audioSampleRate: Double = 44100
    var audioLengthSamples: AVAudioFramePosition = 0

    // A/V Sync Constants
    let syncThresholdSeconds: Double = 0.025  // 25ms - tighter threshold, below human perception (~45ms)
    
    // Audio delay compensation: Video decode is faster than audio engine startup.
    // Delay audio start by this amount to keep them in sync.
    let audioDelayCompensationNanos: UInt64 = 40_000_000  // 40ms - tunable

    // Flag to prevent observer from resyncing during initial playback start
    var isStartingPlayback = false

    // Cancellable for player item status observation during preload
    var preloadCancellable: AnyCancellable?

    // Playback ID to prevent stale completion handlers from interfering
    // Incremented each time startPlayback() is called
    var currentPlaybackId: UInt64 = 0

    init() {
        setupAudioSession()
        setupAudioEngine()
        setupObservers()
        addTimeObserver()
        setupRemoteCommandCenter()
        setupInterruptionObserver()
        setupRouteChangeObserver()
    }
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
}
