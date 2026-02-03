import Foundation
import AVFoundation

extension PlayerViewModel {
    
    func updateEQ(_ values: [Double], preamp: Double) {
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

    /// Toggles between EQ audio (AVAudioEngine) and native video audio (AVPlayer unmuted)
    /// When EQ is enabled: playerNode plays audio with EQ, video is muted
    /// When EQ is disabled: playerNode is silent, video plays its native audio
    func setEQEnabled(_ enabled: Bool) {
        if enabled {
            // Use EQ audio: mute video, ensure audio engine is playing
            player.isMuted = true
            engine.mainMixerNode.outputVolume = 1.0
            if player.timeControlStatus == .playing && !playerNode.isPlaying {
                if !engine.isRunning { try? engine.start() }
                // Resync audio to current video position
                resyncAudio(to: player.currentTime().seconds, force: true)
            }
        } else {
            // Use native video audio: unmute video, silence audio engine
            player.isMuted = false
            engine.mainMixerNode.outputVolume = 0.0
        }
    }
}
