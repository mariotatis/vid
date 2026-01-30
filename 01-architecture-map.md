# Vid Player Architecture Map

## Executive Summary

Vid uses a **dual-pipeline playback architecture** that separates video and audio processing:
- **AVPlayer** (muted) handles video decoding and rendering
- **AVAudioEngine** handles audio decoding, EQ processing, and output

This separation exists to enable a **real-time 6-band parametric equalizer** that cannot be achieved through standard AVPlayer audio processing APIs.

---

## 1. Playback Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           VIDEO PIPELINE                                     │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────────────────────┐   │
│  │  Video   │───▶│   AVPlayer   │───▶│   AVPlayerViewController          │   │
│  │   File   │    │  (isMuted)   │    │   (CustomVideoPlayer wrapper)    │   │
│  │  (.mp4)  │    └──────────────┘    └──────────────────────────────────┘   │
│  └──────────┘           │                                                    │
│                         │ Master Clock (timeControlStatus)                   │
└─────────────────────────┼───────────────────────────────────────────────────┘
                          │
                          │ Synchronized via host time (mach_absolute_time)
                          │
┌─────────────────────────┼───────────────────────────────────────────────────┐
│                         ▼         AUDIO PIPELINE                             │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐    ┌─────────────┐    │
│  │  Audio   │───▶│ AVAudioFile  │───▶│AVAudioPlayer │───▶│ AVAudioUnit │───▶│
│  │   File   │    │  (reading)   │    │    Node      │    │     EQ      │    │
│  │  (.mp4)  │    └──────────────┘    └──────────────┘    │  (6-band)   │    │
│  └──────────┘                                             └──────┬──────┘    │
│                                                                  │           │
│                              ┌────────────────┐    ┌─────────────▼─────────┐ │
│                              │ Audio Hardware │◀───│   mainMixerNode       │ │
│                              │    Output      │    │   (AVAudioEngine)     │ │
│                              └────────────────┘    └───────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Classes and Responsibilities

### 2.1 PlayerViewModel ([PlayerViewModel.swift](Vid/ViewModels/PlayerViewModel.swift))

**Singleton:** `PlayerViewModel.shared`

| Property | Type | Purpose |
|----------|------|---------|
| `player` | `AVPlayer` | Video-only playback (muted) |
| `engine` | `AVAudioEngine` | Audio processing host |
| `playerNode` | `AVAudioPlayerNode` | Audio file playback |
| `eqNode` | `AVAudioUnitEQ` | 6-band parametric EQ |
| `audioFile` | `AVAudioFile?` | Current audio file reference |
| `audioSampleRate` | `Double` | Sample rate (typically 44100/48000) |
| `audioLengthSamples` | `AVAudioFramePosition` | Total audio samples |

**Key Methods:**

| Method | Lines | Purpose |
|--------|-------|---------|
| `play(video:from:settings:)` | 163-193 | Entry point for playback |
| `startPlayback()` | 210-270 | Initialize both pipelines |
| `prerollAndStartSynchronized(from:)` | 273-354 | Synchronized A/V start |
| `resyncAudio(to:force:)` | 484-526 | Drift correction |
| `seek(to:)` | 372-387 | Frame-accurate seeking |
| `togglePlayPause()` | 528-545 | Play/pause coordination |
| `updateEQ(_:preamp:)` | 195-208 | Real-time EQ adjustment |

### 2.2 CustomVideoPlayer ([CustomVideoPlayer.swift](Vid/Views/Player/CustomVideoPlayer.swift))

**UIViewControllerRepresentable wrapper for AVPlayerViewController**

```swift
func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = false    // Custom UI
    controller.updatesNowPlayingInfoCenter = false // Manual control
    return controller
}
```

- Provides native video rendering and PiP support
- Disables native controls in favor of custom overlay
- Video gravity configurable for aspect ratio modes

### 2.3 SettingsStore ([SettingsStore.swift](Vid/Managers/SettingsStore.swift))

**Singleton:** `SettingsStore.shared`

| Property | Type | Persistence |
|----------|------|-------------|
| `eqValues` | `[Double]` (6 values) | UserDefaults |
| `preampValue` | `Double` | UserDefaults |
| `isShuffleOn` | `Bool` | @AppStorage |
| `aspectRatioMode` | `AspectRatioMode` | @AppStorage |

EQ values are observed via Combine and applied reactively:
```swift
settings.$eqValues.combineLatest(settings.$preampValue)
    .sink { [weak self] (eqValues, preampValue) in
        self?.updateEQ(eqValues, preamp: preampValue)
    }
```

---

## 3. Synchronization Mechanisms

### 3.1 Initial Sync: Host Time Synchronization (Lines 324-341)

Both pipelines start at a precise future host time:

```swift
// Calculate host time ~100ms in future
let hostTimeNow = mach_absolute_time()
let delayHostTicks = UInt64(Double(100_000_000) / nanosPerHostTick)
let startHostTime = hostTimeNow + delayHostTicks

// Start audio at precise host time
let audioStartTime = AVAudioTime(hostTime: startHostTime)
playerNode.play(at: audioStartTime)

// Start video at same host time
let cmHostTime = CMClockMakeHostTimeFromSystemUnits(startHostTime)
player.setRate(1.0, time: time, atHostTime: cmHostTime)
```

**Why 100ms delay:** Allows both pipelines to preroll/buffer before synchronized start.

### 3.2 Drift Correction: Event-Based Resync (Lines 484-526)

```swift
private let syncThresholdSeconds: Double = 0.04  // 40ms threshold
```

Resync is triggered by events, NOT periodic timers:
- **Seek operations** (force: true)
- **Play/pause from external sources** (Control Center, lock screen)
- **PiP skip buttons** (timeJumpedNotification)
- **Audio session interruption end**

The algorithm:
1. Calculate current audio position via `playerNode.playerTime(forNodeTime:)`
2. Compare with target video time
3. If drift > 40ms, stop node and reschedule from new position
4. Resume if was playing

### 3.3 Observer-Based Sync Triggers

| Observer | Lines | Trigger |
|----------|-------|---------|
| `timeControlStatus` | 113-133 | External play/pause (Control Center) |
| `timeJumpedNotification` | 136-149 | PiP skip, system seek |
| `interruptionNotification` | 436-467 | Phone call, Siri, etc. |
| `routeChangeNotification` | 469-482 | Headphone unplug |

### 3.4 Sync State Flags

| Flag | Purpose |
|------|---------|
| `isStartingPlayback` | Prevents observer-triggered resync during initial start |
| `isSeeking` | Prevents time updates during manual seek |

---

## 4. Buffering and Preloading Strategy

### 4.1 Video Preloading

```swift
// Wait for AVPlayerItem to be ready
preloadCancellable = playerItem.publisher(for: \.status)
    .filter { $0 == .readyToPlay }
    .first()
    .sink { _ in
        self?.prerollAndStartSynchronized(from: .zero)
    }
```

```swift
// Preroll video buffer before starting
player.preroll(atRate: 1.0) { prerollFinished in
    // Then start synchronized playback
}
```

### 4.2 Audio Preloading

Audio is loaded entirely into memory via `AVAudioFile`:
```swift
audioFile = try AVAudioFile(forReading: video.url)
audioSampleRate = file.processingFormat.sampleRate
audioLengthSamples = file.length
```

Segments are scheduled on demand:
```swift
playerNode.scheduleSegment(
    file,
    startingFrame: targetSample,
    frameCount: remainingSamples,
    at: nil
)
```

### 4.3 Format Handling

Audio engine connections are updated per-file to match source format:
```swift
private func reconnectAudioNodes(with format: AVAudioFormat) {
    engine.disconnectNodeOutput(playerNode)
    engine.disconnectNodeOutput(eqNode)
    engine.connect(playerNode, to: eqNode, format: format)
    engine.connect(eqNode, to: engine.mainMixerNode, format: format)
}
```

---

## 5. Seek Handling

### 5.1 User-Initiated Seek (Lines 372-387)

```swift
func seek(to time: Double) {
    isSeeking = true

    // Frame-accurate video seek
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
        // Force audio resync after video seek completes
        self.resyncAudio(to: time, force: true)
        self.isSeeking = false
    }
}
```

### 5.2 System-Initiated Seek (PiP skip, Control Center scrubber)

Detected via `AVPlayerItem.timeJumpedNotification`:
```swift
NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)
    .sink { _ in
        guard !self.isSeeking, !self.isStartingPlayback else { return }
        // Full synchronized preroll for system seeks
        self.prerollAndStartSynchronized(from: self.player.currentTime())
    }
```

---

## 6. Rate Changes and Interruptions

### 6.1 Playback Rate

Currently hardcoded to 1.0x only:
```swift
player.setRate(1.0, time: time, atHostTime: cmHostTime)
```

No variable speed playback implemented.

### 6.2 Audio Session Interruptions (Lines 436-467)

| Event | Action |
|-------|--------|
| `.began` | Pause playerNode |
| `.ended` with `.shouldResume` | Restart engine, resync, resume both |

### 6.3 Route Changes (Lines 469-482)

| Event | Action |
|-------|--------|
| `.oldDeviceUnavailable` | Pause playback (headphone unplug) |

---

## 7. Background Audio & Lock Screen

### 7.1 Audio Session Configuration (Lines 56-64)

```swift
try AVAudioSession.sharedInstance().setCategory(
    .playback,          // Background audio enabled
    mode: .moviePlayback // Video content optimization
)
try AVAudioSession.sharedInstance().setActive(true)
UIApplication.shared.beginReceivingRemoteControlEvents()
```

### 7.2 Remote Command Center (Lines 549-603)

| Command | Handler |
|---------|---------|
| Play/Pause/Toggle | `togglePlayPause()` |
| Next Track | `playNext()` |
| Previous Track | `playPrevious()` |
| Change Position | `seek(to:)` |

Skip forward/backward commands explicitly disabled.

### 7.3 Now Playing Info (Lines 605-629)

Updated on: play, pause, seek, track change.

---

## 8. Picture-in-Picture Support

PiP is provided automatically by `AVPlayerViewController`:
- Enabled via `player.allowsExternalPlayback = true`
- Skip buttons detected via `timeJumpedNotification`
- Full synchronized preroll on PiP seek events

---

## 9. Audio Processing: Equalizer

### 9.1 EQ Node Configuration (Lines 76-84)

```swift
let frequencies: [Float] = [60, 150, 400, 1000, 2400, 15000]
for (i, freq) in frequencies.enumerated() {
    let band = eqNode.bands[i]
    band.frequency = freq
    band.bypass = false
    band.filterType = (i == 0) ? .lowShelf
                    : (i == frequencies.count - 1) ? .highShelf
                    : .parametric
    band.bandwidth = 0.5
}
```

### 9.2 Gain Calculation (Lines 195-207)

```swift
// Band: 0.0-1.0 → -12dB to +12dB
let bandGain = Float((value - 0.5) * 24)
// Preamp: 0.0-1.0 → -15dB to +15dB
let preampGain = Float((preamp - 0.5) * 30)
// Combined
eqNode.bands[i].gain = bandGain + preampGain
```

---

## 10. Data Flow Summary

```
User taps Play
       │
       ▼
play(video:from:settings:)
       │
       ├── Setup queue (shuffle if needed)
       ├── Subscribe to EQ settings changes
       │
       ▼
startPlayback()
       │
       ├── Cancel previous preload
       ├── Stop playerNode
       ├── Update watch statistics
       │
       ├── [VIDEO] Create AVPlayerItem, configure AVPlayer (muted)
       │
       ├── [AUDIO] Load AVAudioFile, extract format/sample info
       │
       ├── Wait for AVPlayerItem.status == .readyToPlay
       │
       ▼
prerollAndStartSynchronized(from:)
       │
       ├── Stop/reset playerNode
       ├── Reconnect nodes with file's audio format
       ├── Calculate start sample from CMTime
       ├── Schedule audio segment
       ├── Seek video to position
       ├── Preroll video
       │
       ▼
[Synchronized Start]
       │
       ├── Calculate future host time (mach_absolute_time + 100ms)
       ├── playerNode.play(at: AVAudioTime(hostTime:))
       ├── player.setRate(1.0, time:, atHostTime:)
       │
       ▼
[Playback Running]
       │
       ├── AVPlayer drives video rendering
       ├── AVAudioEngine drives audio output with EQ
       ├── Periodic time observer updates UI (0.5s interval)
       │
       ▼
[Events Trigger Resync]
       │
       ├── Seek → resyncAudio(force: true)
       ├── External play → resyncAudio(force: true)
       ├── PiP skip → prerollAndStartSynchronized()
       ├── Interruption end → resyncAudio(force: true)
```

---

## 11. File Organization

```
Vid/
├── ViewModels/
│   └── PlayerViewModel.swift      # Core playback logic (651 lines)
│
├── Views/Player/
│   ├── CustomVideoPlayer.swift    # AVPlayerViewController wrapper
│   ├── PlayerView.swift           # Full-screen player UI
│   ├── PlayerControlsOverlay.swift # Controls UI
│   ├── EqualizerView.swift        # 6-band EQ UI
│   └── VolumeOverlay.swift        # Volume gesture handling
│
├── Managers/
│   ├── SettingsStore.swift        # EQ/settings persistence
│   ├── VideoManager.swift         # Video library
│   └── PlaylistManager.swift      # Playlists
│
└── Models/
    ├── Video.swift                # Video metadata
    └── Playlist.swift             # Playlist model
```

---

## 12. Known Sync Edge Cases

| Scenario | Handling | Risk |
|----------|----------|------|
| Very long video (>2 hours) | Drift may accumulate | Low - 40ms threshold catches drift |
| Rapid seek spam | Multiple resync calls | Low - state flags prevent overlap |
| Format mismatch | Engine reconnection | Low - handled per-file |
| Background → foreground | Interruption observer | Low - full resync on resume |
| PiP → fullscreen | No special handling needed | None - same player instance |
| AirPlay | `allowsExternalPlayback = true` | Medium - sync with external display untested |
