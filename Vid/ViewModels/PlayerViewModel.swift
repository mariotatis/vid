import Foundation
import AVKit
import AVFoundation
import Combine
import MediaPlayer

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
        setupRemoteCommandCenter()
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
        settingsCancellable = settings.$eqValues.combineLatest(settings.$preampValue)
            .sink { [weak self] (eqValues, preampValue) in
                 self?.updateEQ(eqValues, preamp: preampValue)
            }
        
        // Apply initial EQ
        updateEQ(settings.eqValues, preamp: settings.preampValue)
        
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
    
    private func updateEQ(_ values: [Double], preamp: Double) {
        for (i, value) in values.enumerated() {
            guard i < eqNode.bands.count else { break }
            
            // Map individual band (0.0-1.0) to -12dB to +12dB
            let bandGain = Float((value - 0.5) * 24)
            // Map preamp (0.0-1.0) to -15dB to +15dB
            let preampGain = Float((preamp - 0.5) * 30)
            
            // Final gain combined, clamped to standard ranges if necessary 
            // AVAudioUnitEQ usually supports quite a wide range (-24 to 24 or more)
            eqNode.bands[i].gain = bandGain + preampGain
        }
    }
    
    private func startPlayback() {
        guard let video = currentVideo else { return }
        
        // 1. Prepare AVPlayer (Video Only - Muted)
        let playerItem = AVPlayerItem(url: video.url)
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = true
        player.allowsExternalPlayback = true
        
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
        updateNowPlayingInfo()
        
        // Update duration
        Task {
            if let duration = try? await playerItem.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                await MainActor.run {
                    self.duration = seconds
                    self.updateNowPlayingInfo()
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
        updateNowPlayingInfo()
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
        if currentTime > 5 {
            seek(to: 0)
            return
        }
        
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
        updateNowPlayingInfo()
    }
    
    // MARK: - Remote Commands & Metadata
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play/Pause
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // Track Skipping
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        
        // Disable behavior that might interfere (like 15s skip)
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: positionEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        
        if let video = currentVideo {
            nowPlayingInfo[MPMediaItemPropertyTitle] = video.name
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func updateShuffleState(isOn: Bool) {
        self.isShuffleOn = isOn
        guard let current = currentVideo else { return }
        
        if isOn {
            // Shuffle: Create new shuffled queue, ensure current is first
            var newQueue = originalQueue.shuffled()
            if let index = newQueue.firstIndex(of: current) {
                newQueue.swapAt(0, index)
            } else {
                newQueue.insert(current, at: 0)
            }
            self.queue = newQueue
            self.currentIndex = 0
        } else {
            // Unshuffle: Revert to original order, find current index
            self.queue = originalQueue
            self.currentIndex = originalQueue.firstIndex(of: current) ?? 0
        }
    }
}
