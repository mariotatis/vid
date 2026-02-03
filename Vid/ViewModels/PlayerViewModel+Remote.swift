import Foundation
import MediaPlayer
import AVFoundation
import Combine

extension PlayerViewModel {
    
    // MARK: - Remote Commands & Metadata
    
    func setupRemoteCommandCenter() {
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
    
    func updateNowPlayingInfo() {
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
    
    func setupInterruptionObserver() {
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
    
    func setupRouteChangeObserver() {
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
    
    func setupObservers() {
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
    
    func addTimeObserver() {
        // AVPlayer is the master clock for video timing
        // Audio sync is handled via event-based resync (seek, play/pause, time jumps)
        // not periodic correction, to avoid audio interruptions
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            self.currentTime = time.seconds
        }
    }
    
    func donatePlayPlaylistActivity(for video: Video) {
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
}
