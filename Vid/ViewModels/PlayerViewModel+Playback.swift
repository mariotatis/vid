import Foundation
import AVFoundation
import MediaPlayer
import Combine

extension PlayerViewModel {
    
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
    
    func startPlayback() {
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
    func continuePlaybackSetup(for video: Video, playbackId: UInt64) {
        // 2. Prepare AVPlayer (Video Only - Muted when EQ is enabled)
        let playerItem = AVPlayerItem(url: video.url)
        player.replaceCurrentItem(with: playerItem)
        
        // Apply EQ enabled state: when EQ on, video muted + audio engine at full volume
        // When EQ off, video unmuted + audio engine silenced
        let eqEnabled = SettingsStore.shared.isEQEnabled
        player.isMuted = eqEnabled
        engine.mainMixerNode.outputVolume = eqEnabled ? 1.0 : 0.0
        
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
    func playVideoOnly(from time: CMTime) {
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
    func rescheduleAudioOnly(to time: Double) {
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
