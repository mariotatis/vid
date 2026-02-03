import Foundation
import AVFoundation

extension PlayerViewModel {
    
    func setupAudioEngine() {
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
    func reconnectAudioNodes(with format: AVAudioFormat) {
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
    
    /// Validates and repairs audio engine state if needed
    func ensureAudioEngineHealthy() -> Bool {
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
    func prepareAudioFile(for video: Video) -> Bool {
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
}
