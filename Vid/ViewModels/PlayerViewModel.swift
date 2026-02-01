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

    // A/V Sync Constants
    private let syncThresholdSeconds: Double = 0.025  // 25ms - tighter threshold, below human perception (~45ms)
    
    // Audio delay compensation: Video decode is faster than audio engine startup.
    // Delay audio start by this amount to keep them in sync.
    private let audioDelayCompensationNanos: UInt64 = 40_000_000  // 40ms - tunable

    // Flag to prevent observer from resyncing during initial playback start
    private var isStartingPlayback = false

    // Cancellable for player item status observation during preload
    private var preloadCancellable: AnyCancellable?

    // Playback ID to prevent stale completion handlers from interfering
    // Incremented each time startPlayback() is called
    private var currentPlaybackId: UInt64 = 0

    init() {
        setupAudioSession()
        setupAudioEngine()
        setupObservers()
        addTimeObserver()
        setupRemoteCommandCenter()
        setupInterruptionObserver()
        setupRouteChangeObserver()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(playerNode)
        engine.attach(eqNode)

        // Initial connection with default format (will be reconnected per-file)
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

    /// Reconnects audio engine nodes with the format of the current audio file
    private func reconnectAudioNodes(with format: AVAudioFormat) {
        // Stop engine to allow reconnection
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }

        // Disconnect and reconnect with new format
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eqNode)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        // Restart engine
        if wasRunning { try? engine.start() }
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.playNext()
            }
            .store(in: &cancellables)
            
        // Observe player status to keep isPlaying and Audio Engine in sync
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                self.isPlaying = (status == .playing)

                // Skip audio adjustments while seeking - seek() handles audio sync
                guard !self.isSeeking else {
                    self.updateNowPlayingInfo()
                    return
                }

                if status == .playing {
                    // Only resync if this is a resume from external source (Control Center, etc.)
                    // NOT during initial playback start (we handle that in startPlayback)
                    if !self.isStartingPlayback {
                        if !self.engine.isRunning { try? self.engine.start() }
                        // Resync audio to video position when resuming from external control
                        self.resyncAudio(to: self.player.currentTime().seconds, force: true)
                    }
                } else if status == .paused {
                    self.playerNode.pause()
                }

                self.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
            
        // Observe time jumps (e.g., seeking via system controls like PiP skip buttons)
        NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self,
                      !self.isSeeking,
                      !self.isStartingPlayback else { return }
                
                // Use synchronized preroll for PiP skip to ensure A/V sync
                let currentTime = self.player.currentTime()
                
                // If we were playing, restart synchronized.
                // If we were paused, just resync the audio engine state but stay paused.
                if self.player.timeControlStatus == .playing {
                    self.player.pause()
                    self.playerNode.stop()
                    self.isStartingPlayback = true
                    self.prerollAndStartSynchronized(from: currentTime)
                } else {
                     // Just resync audio position without starting playback
                    self.resyncAudio(to: currentTime.seconds, force: true)
                }
            }
            .store(in: &cancellables)
    }
    
    private func addTimeObserver() {
        // AVPlayer is the master clock for video timing
        // Audio sync is handled via event-based resync (seek, play/pause, time jumps)
        // not periodic correction, to avoid audio interruptions
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
        settings.lastVideoId = video.id
        
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

    // MARK: - Audio Sync Helpers

    #if DEBUG
    private func logSync(_ message: String) {
        let timestamp = Date().timeIntervalSince1970
        print("[SYNC \(String(format: "%.3f", timestamp))]: \(message)")
    }
    #else
    private func logSync(_ message: String) {}
    #endif

    /// Validates and repairs audio engine state if needed
    private func ensureAudioEngineHealthy() -> Bool {
        guard engine.isRunning else {
            do {
                try engine.start()
                logSync("Audio engine started successfully")
                return engine.isRunning
            } catch {
                logSync("Failed to start audio engine: \(error)")
                return false
            }
        }
        return true
    }

    /// Prepares audio file for playback, returns success status
    private func prepareAudioFile(for video: Video) -> Bool {
        do {
            audioFile = try AVAudioFile(forReading: video.url)
            if let file = audioFile {
                audioSampleRate = file.processingFormat.sampleRate
                audioLengthSamples = file.length
                logSync("Audio file loaded: \(video.url.lastPathComponent), sampleRate: \(audioSampleRate), samples: \(audioLengthSamples)")
                return true
            }
            return false
        } catch {
            logSync("Failed to load audio file: \(error)")
            return false
        }
    }

    private func startPlayback() {
        guard let video = currentVideo else { return }

        // Increment playback ID to invalidate any stale completion handlers
        currentPlaybackId &+= 1
        let playbackId = currentPlaybackId

        logSync("Starting playback for: \(video.url.lastPathComponent) [id=\(playbackId)]")

        // Cancel any previous preload
        preloadCancellable?.cancel()
        preloadCancellable = nil

        // Stop and fully reset audio node to clear any pending schedules
        playerNode.stop()
        playerNode.reset()

        // Update watch status
        if let index = VideoManager.shared.videos.firstIndex(where: { $0.id == video.id }) {
            VideoManager.shared.videos[index].isWatched = true
            VideoManager.shared.videos[index].watchCount += 1
            VideoManager.shared.saveVideosToDisk()
        }

        isStartingPlayback = true
        showPlayer = true

        // Ensure audio engine is healthy before proceeding
        _ = ensureAudioEngineHealthy()

        // 1. Prepare AVAudioEngine (Audio) FIRST - validate before video setup
        let audioReady = prepareAudioFile(for: video)
        if !audioReady {
            // Wait briefly and retry once (file system timing)
            logSync("Audio file load failed, retrying after 100ms...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.currentPlaybackId == playbackId else {
                    // Playback was superseded by another track
                    return
                }
                let retrySuccess = self.prepareAudioFile(for: video)
                if !retrySuccess {
                    self.logSync("WARNING: Playing video without audio after retry")
                } else {
                    // Reconnect audio nodes with correct format for this video
                    self.reconnectAudioNodes(with: self.audioFile!.processingFormat)
                }
                self.continuePlaybackSetup(for: video, playbackId: playbackId)
            }
            return
        }

        // Reconnect audio nodes with correct format for this video
        if let file = audioFile {
            reconnectAudioNodes(with: file.processingFormat)
        }

        continuePlaybackSetup(for: video, playbackId: playbackId)
    }

    /// Continues playback setup after audio file is prepared (or retry completed)
    private func continuePlaybackSetup(for video: Video, playbackId: UInt64) {
        // 2. Prepare AVPlayer (Video Only - Muted)
        let playerItem = AVPlayerItem(url: video.url)
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = true
        player.allowsExternalPlayback = true
        // Disable automatic stalling for precise timing control
        player.automaticallyWaitsToMinimizeStalling = false

        // 3. Wait for video to be ready to play, then preroll and start synchronized
        preloadCancellable = playerItem.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.currentPlaybackId == playbackId else {
                    // Playback was superseded by another track
                    return
                }
                self.logSync("PlayerItem ready, starting synchronized playback [id=\(playbackId)]")
                self.prerollAndStartSynchronized(from: .zero, playbackId: playbackId)
            }

        // Get duration
        Task {
            let duration = playerItem.asset.duration
            let seconds = CMTimeGetSeconds(duration)
            await MainActor.run {
                self.duration = seconds
                self.updateNowPlayingInfo()
            }
        }

        // 4. Donate User Activity for Siri (iOS 15 legacy support)
        donatePlayPlaylistActivity(for: video)
    }

    /// Plays video only (fallback when audio is unavailable)
    private func playVideoOnly(from time: CMTime) {
        logSync("Playing video only (no audio)")
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.player.play()
            self?.isPlaying = true
            self?.updateNowPlayingInfo()
            // Delay clearing isStartingPlayback to avoid spurious notifications
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isStartingPlayback = false
            }
        }
    }

    /// Starts audio and video playback in sync (simplified version matching resyncAudio pattern)
    private func prerollAndStartSynchronized(from time: CMTime, playbackId: UInt64? = nil) {
        // Validate audio is ready (unless video-only mode)
        guard let file = audioFile else {
            playVideoOnly(from: time)
            return
        }

        // Ensure engine is running
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else {
            logSync("ERROR: Cannot start audio engine, falling back to video-only")
            playVideoOnly(from: time)
            return
        }

        // Calculate audio start frame
        let startTimeSeconds = max(0, CMTimeGetSeconds(time))
        var targetSample = AVAudioFramePosition(startTimeSeconds * audioSampleRate)
        targetSample = max(0, min(targetSample, audioLengthSamples - 1))

        // Schedule audio segment (same pattern as resyncAudio which works)
        let remainingSamples = AVAudioFrameCount(max(0, audioLengthSamples - targetSample))
        guard remainingSamples > 0 else {
            playVideoOnly(from: time)
            return
        }

        playerNode.stop()
        playerNode.scheduleSegment(file, startingFrame: targetSample, frameCount: remainingSamples, at: nil, completionHandler: nil)

        // Seek video to target time, then start both
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished else { return }
            // Check if playback was superseded
            if let id = playbackId, self.currentPlaybackId != id { return }

            // Start engine if needed
            if !self.engine.isRunning { try? self.engine.start() }

            // Calculate a near-future host time for synchronized start
            var timebaseInfo = mach_timebase_info()
            mach_timebase_info(&timebaseInfo)
            let nanosPerHostTick = Double(timebaseInfo.numer) / Double(timebaseInfo.denom)

            let hostTimeNow = mach_absolute_time()
            let delayNanos: UInt64 = 50_000_000  // 50ms delay for sync
            let delayHostTicks = UInt64(Double(delayNanos) / nanosPerHostTick)
            let startHostTime = hostTimeNow + delayHostTicks

            // Start VIDEO at base host time (video decode is faster)
            let cmHostTime = CMClockMakeHostTimeFromSystemUnits(startHostTime)
            self.player.setRate(1.0, time: time, atHostTime: cmHostTime)

            // Start AUDIO slightly later to compensate for pipeline latency
            let audioDelayTicks = UInt64(Double(self.audioDelayCompensationNanos) / nanosPerHostTick)
            let audioStartHostTime = startHostTime + audioDelayTicks
            let audioStartTime = AVAudioTime(hostTime: audioStartHostTime)
            self.playerNode.play(at: audioStartTime)

            self.isPlaying = true
            self.updateNowPlayingInfo()

            // Delay clearing isStartingPlayback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isStartingPlayback = false
            }
        }
    }
    
    private func donatePlayPlaylistActivity(for video: Video) {
        let activity = NSUserActivity(activityType: "com.vid.playPlaylist")
        activity.title = "Play \(video.name)"
        activity.userInfo = ["videoUrl": video.url.absoluteString]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier("play_\(video.name)")
        
        // Localized Title for Shortcuts app
        if Locale.current.identifier.contains("es") {
            activity.title = "Reproducir \(video.name)"
        }
        
        activity.becomeCurrent()
    }
    
    func seek(to time: Double) {
        self.isSeeking = true

        // Capture play state BEFORE seeking - we'll restore this state after
        let wasPlaying = player.timeControlStatus == .playing

        // Seek Video
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished else { return }

            // Reschedule audio at new position (don't auto-play, we control that)
            self.rescheduleAudioOnly(to: time)

            // Restore play state - only play if we were playing before
            if wasPlaying {
                // Start audio playback
                if !self.engine.isRunning { try? self.engine.start() }
                self.playerNode.play()
            }

            self.updateNowPlayingInfo()
            
            // Delay clearing isSeeking to protect against late-arriving timeJumped notifications
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isSeeking = false
            }
        }

        currentTime = time
    }

    /// Reschedules audio at the given time WITHOUT starting playback
    private func rescheduleAudioOnly(to time: Double) {
        guard let file = audioFile else { return }

        let clampedTime = max(0, time)
        var targetSample = AVAudioFramePosition(clampedTime * audioSampleRate)
        targetSample = max(0, min(targetSample, audioLengthSamples - 1))

        playerNode.stop()

        let remainingSamples = AVAudioFrameCount(max(0, audioLengthSamples - targetSample))
        if remainingSamples > 0 {
            playerNode.scheduleSegment(file, startingFrame: targetSample, frameCount: remainingSamples, at: nil, completionHandler: nil)
        }
    }
    
    func playNext() {
        guard !queue.isEmpty else { return }

        var nextIndex = currentIndex + 1
        if nextIndex >= queue.count {
            nextIndex = 0 // Loop
        }

        currentIndex = nextIndex
        currentVideo = queue[currentIndex]
        if let video = currentVideo {
            SettingsStore.shared.lastVideoId = video.id
        }
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
        if let video = currentVideo {
            SettingsStore.shared.lastVideoId = video.id
        }
        startPlayback()
    }
    
    func stop() {
        player.pause()
        playerNode.stop()
        engine.stop()
        isPlaying = false
        showPlayer = false
        // Resign activity
        NSUserActivity.deleteAllSavedUserActivities { }
    }
    
    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .began {
                self.playerNode.pause()
                // AVPlayer handles its own pause usually on interruption, but we sync state
            } else if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        // Restart engine and resume if it was playing
                        if !self.engine.isRunning {
                            try? self.engine.start()
                        }

                        // Resync audio time with video and resume both
                        let currentTime = self.player.currentTime().seconds
                        self.resyncAudio(to: currentTime, force: true)

                        self.player.play()
                        if !self.playerNode.isPlaying {
                            self.playerNode.play()
                        }
                    }
                }
            }
        }
    }
    
    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
            
            if reason == .oldDeviceUnavailable {
                // E.g., Headphones unplugged
                if self?.player.timeControlStatus == .playing {
                    self?.togglePlayPause() // Pause
                }
            }
        }
    }
    
    private func resyncAudio(to time: Double, force: Bool = false) {
        // Sanitize input to prevent negative sample calculations
        let clampedTime = max(0, time)
        guard let file = audioFile else { return }

        // 1. Calculate the target sample
        // Note: We don't compensate for output latency here as it can cause position errors.
        // The initial sync when AVPlayer starts handles alignment, and drift correction
        // catches any significant divergence.
        var targetSample = AVAudioFramePosition(clampedTime * audioSampleRate)

        // Ensure targetSample is within bounds (0 to length - 1)
        targetSample = max(0, min(targetSample, audioLengthSamples - 1))

        // 2. Optimization: If we are already playing and very close to the target, don't interrupt
        // Unless we are 'forcing' a sync (e.g., manual seeker release)
        if playerNode.isPlaying && !force {
            if let lastRenderTime = playerNode.lastRenderTime,
               let playerTime = playerNode.playerTime(forNodeTime: lastRenderTime),
               playerTime.isSampleTimeValid {
                let currentSample = playerTime.sampleTime
                let diff = abs(targetSample - currentSample)
                let diffSeconds = Double(diff) / audioSampleRate
                if diffSeconds < syncThresholdSeconds { return }
            }
        }

        let wasPlaying = playerNode.isPlaying || player.timeControlStatus == .playing

        logSync("Resyncing audio to \(clampedTime)s (force: \(force), wasPlaying: \(wasPlaying))")

        // 3. Reschedule
        playerNode.stop()
        let remainingSamples = AVAudioFrameCount(max(0, audioLengthSamples - targetSample))
        if remainingSamples > 0 {
            playerNode.scheduleSegment(file, startingFrame: targetSample, frameCount: remainingSamples, at: nil, completionHandler: nil)

            // 4. Resume if it was playing, with precise timing
            if wasPlaying {
                if !engine.isRunning { try? engine.start() }

                // Calculate a near-future host time for synchronized restart
                var timebaseInfo = mach_timebase_info()
                mach_timebase_info(&timebaseInfo)
                let nanosPerHostTick = Double(timebaseInfo.numer) / Double(timebaseInfo.denom)

                let hostTimeNow = mach_absolute_time()
                let delayNanos: UInt64 = 30_000_000  // 30ms - enough for scheduling
                let delayHostTicks = UInt64(Double(delayNanos) / nanosPerHostTick)
                let restartHostTime = hostTimeNow + delayHostTicks

                // Delay audio start to compensate for video decode being faster
                let audioDelayTicks = UInt64(Double(audioDelayCompensationNanos) / nanosPerHostTick)
                let audioRestartHostTime = restartHostTime + audioDelayTicks
                let audioRestartTime = AVAudioTime(hostTime: audioRestartHostTime)
                playerNode.play(at: audioRestartTime)
            }
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
            playerNode.pause()
        } else {
            guard let file = audioFile else {
                // No audio, just play video
                player.play()
                return
            }

            // Prevent observer from interfering
            isStartingPlayback = true

            if !engine.isRunning { try? engine.start() }

            // Schedule audio at current video position
            let currentTime = player.currentTime().seconds
            let clampedTime = max(0, currentTime)
            var targetSample = AVAudioFramePosition(clampedTime * audioSampleRate)
            targetSample = max(0, min(targetSample, audioLengthSamples - 1))

            playerNode.stop()
            let remainingSamples = AVAudioFrameCount(max(0, audioLengthSamples - targetSample))
            if remainingSamples > 0 {
                playerNode.scheduleSegment(file, startingFrame: targetSample, frameCount: remainingSamples, at: nil, completionHandler: nil)
            }

            // Start both at synchronized host time
            var timebaseInfo = mach_timebase_info()
            mach_timebase_info(&timebaseInfo)
            let nanosPerHostTick = Double(timebaseInfo.numer) / Double(timebaseInfo.denom)

            let hostTimeNow = mach_absolute_time()
            let delayNanos: UInt64 = 30_000_000  // 30ms
            let delayHostTicks = UInt64(Double(delayNanos) / nanosPerHostTick)
            let startHostTime = hostTimeNow + delayHostTicks

            // Start VIDEO at base host time (video decode is faster)
            let cmHostTime = CMClockMakeHostTimeFromSystemUnits(startHostTime)
            let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
            player.setRate(1.0, time: cmTime, atHostTime: cmHostTime)

            // Start AUDIO slightly later to compensate for pipeline latency
            let audioDelayTicks = UInt64(Double(audioDelayCompensationNanos) / nanosPerHostTick)
            let audioStartHostTime = startHostTime + audioDelayTicks
            let audioStartTime = AVAudioTime(hostTime: audioStartHostTime)
            playerNode.play(at: audioStartTime)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isStartingPlayback = false
            }
        }
        // isPlaying will be updated by the observer on timeControlStatus
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
        // Setting preferredIntervals to empty and removing targets can help force track commands
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.preferredIntervals = []
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.preferredIntervals = []
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.removeTarget(nil)
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.removeTarget(nil)
        
        // Explicitly enable next/previous
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        
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
            nowPlayingInfo[MPMediaItemPropertyArtist] = "Vid"
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            
            // Add Artwork
            if let image = ThumbnailCache.shared.thumbnail(for: video.url) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                    return image
                }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }

            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
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
