import Foundation
import AVFoundation

extension PlayerViewModel {
    
    // MARK: - Audio Sync Helpers

    #if DEBUG
    func logSync(_ message: String) {
        let timestamp = Date().timeIntervalSince1970
        print("[SYNC \(String(format: "%.3f", timestamp))]: \(message)")
    }
    #else
    func logSync(_ message: String) {}
    #endif
    
    func resyncAudio(to time: Double, force: Bool = false) {
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
    
    /// Starts audio and video playback in sync (simplified version matching resyncAudio pattern)
    func prerollAndStartSynchronized(from time: CMTime, playbackId: UInt64? = nil) {
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
}
