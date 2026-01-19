import Foundation
import AVKit
import AVFoundation
import Combine

class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer = AVPlayer()
    @Published var currentVideo: Video?
    @Published var isPlaying: Bool = false
    @Published var showPlayer: Bool = false
    
    // Audio Engine Components
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 6)
    
    private var queue: [Video] = []
    private var originalQueue: [Video] = []
    private var currentIndex: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private var settingsCancellable: AnyCancellable?
    
    var isShuffleOn: Bool = false
    
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isSeeking = false
    
    // Audio File State
    private var audioFile: AVAudioFile?
    private var audioSampleRate: Double = 44100
    private var audioLengthSamples: AVAudioFramePosition = 0
    
    init() {
        setupAudioSession()
        setupAudioEngine()
        setupObservers()
        addTimeObserver()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(playerNode)
        engine.attach(eqNode)
        
        // Connect nodes: Player -> EQ -> MainMixer
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        
        // Configure EQ Bands
        let frequencies: [Float] = [60, 150, 400, 1000, 2400, 15000]
        for (i, freq) in frequencies.enumerated() {
            let band = eqNode.bands[i]
            band.frequency = freq
            band.bypass = false
            band.filterType = (i == 0) ? .lowShelf : (i == frequencies.count - 1) ? .highShelf : .parametric
            band.bandwidth = 0.5
        }
        
        try? engine.start()
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.playNext()
            }
            .store(in: &cancellables)
    }
    
    private func addTimeObserver() {
        // Sync Logic: We use AVPlayer's time as the master usually, 
        // but since we are driving Audio separately, we should use PlayerNode's time?
        // Actually, for simplicity and UI sync, we will continue to trust AVPlayer's clock 
        // because the UI (Slider) is bound to it and VSync matters for video.
        // We just need to make sure Audio doesn't drift too much.
        // For this implementation, we will perform a "Blind Sync": Start both together.
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            self.currentTime = time.seconds
        }
    }
    
    func play(video: Video, from list: [Video], settings: SettingsStore) {
        self.isShuffleOn = settings.isShuffleOn
        self.originalQueue = list
        
        // Observe settings for real-time EQ updates
        settingsCancellable = settings.$eqValues.sink { [weak self] values in
             self?.updateEQ(values)
        }
        // Apply initial EQ
        updateEQ(settings.eqValues)
        
        if isShuffleOn {
            self.queue = list.shuffled()
            if let index = self.queue.firstIndex(of: video) {
                self.queue.swapAt(0, index)
            } else {
                self.queue.insert(video, at: 0)
            }
            self.currentIndex = 0
        } else {
            self.queue = list
            self.currentIndex = list.firstIndex(of: video) ?? 0
        }
        
        self.currentVideo = video
        startPlayback()
    }
    
    private func updateEQ(_ values: [Double]) {
        for (i, value) in values.enumerated() {
            guard i < eqNode.bands.count else { break }
            // Map 0.0-1.0 to -12dB to +12dB
            let gain = Float((value - 0.5) * 24)
            eqNode.bands[i].gain = gain
        }
    }
    
    private func startPlayback() {
        guard let video = currentVideo else { return }
        
        // 1. Prepare AVPlayer (Video Only - Muted)
        let playerItem = AVPlayerItem(url: video.url)
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = true
        player.allowsExternalPlayback = false
        
        // 2. Prepare AVAudioEngine (Audio)
        do {
            audioFile = try AVAudioFile(forReading: video.url)
            if let file = audioFile {
                audioSampleRate = file.processingFormat.sampleRate
                audioLengthSamples = file.length
                
                playerNode.stop()
                playerNode.scheduleFile(file, at: nil, completionHandler: nil)
            }
        } catch {
            print("Failed to load audio file: \(error)")
        }
        
        // 3. Start Both
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
        player.play()
        
        isPlaying = true
        showPlayer = true
        
        // Update duration
        Task {
            if let duration = try? await playerItem.asset.load(.duration) {
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(duration)
                }
            }
        }
    }
    
    func seek(to time: Double) {
        // Seek Video
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Seek Audio
        if let file = audioFile {
            playerNode.stop()
            
            let startSample = AVAudioFramePosition(time * audioSampleRate)
            let remainingSamples = AVAudioFrameCount(max(0, audioLengthSamples - startSample))
            
            if remainingSamples > 0 {
                playerNode.scheduleSegment(file, startingFrame: startSample, frameCount: remainingSamples, at: nil, completionHandler: nil)
                if isPlaying {
                    playerNode.play()
                }
            }
        }
        
        currentTime = time
    }
    
    func playNext() {
        guard !queue.isEmpty else { return }
        
        var nextIndex = currentIndex + 1
        if nextIndex >= queue.count {
            nextIndex = 0 // Loop
        }
        
        currentIndex = nextIndex
        currentVideo = queue[currentIndex]
        startPlayback()
    }
    
    func playPrevious() {
        guard !queue.isEmpty else { return }
        
        var prevIndex = currentIndex - 1
        if prevIndex < 0 {
            prevIndex = queue.count - 1 // Loop back to end
        }
        
        currentIndex = prevIndex
        currentVideo = queue[currentIndex]
        startPlayback()
    }
    
    func stop() {
        player.pause()
        playerNode.stop()
        engine.stop()
        isPlaying = false
        showPlayer = false
    }
    
    func togglePlayPause() {
        if isPlaying {
            player.pause()
            playerNode.pause()
        } else {
            if !engine.isRunning { try? engine.start() }
            player.play()
            playerNode.play()
        }
        isPlaying.toggle()
    }
}
