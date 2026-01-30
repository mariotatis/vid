# Vid Architecture Map

## Dual-Pipeline Playback

Vid separates video and audio processing to enable real-time EQ:
- **AVPlayer** (muted): video decoding/rendering via `AVPlayerViewController`
- **AVAudioEngine**: audio with 6-band EQ → `AVAudioPlayerNode → AVAudioUnitEQ → mainMixerNode`

Both pipelines start synchronized via `mach_absolute_time` host clock.

---

## Core Components

### PlayerViewModel (Singleton: `.shared`)

**Properties:**
| Name | Type | Purpose |
|------|------|---------|
| `player` | AVPlayer | Video-only (muted) |
| `engine` | AVAudioEngine | Audio processing host |
| `playerNode` | AVAudioPlayerNode | Audio playback |
| `eqNode` | AVAudioUnitEQ | 6-band parametric EQ |
| `audioFile` | AVAudioFile? | Current audio reference |
| `audioSampleRate` | Double | Sample rate (44100/48000) |
| `audioLengthSamples` | AVAudioFramePosition | Total samples |
| `queue` / `originalQueue` | [Video] | Playback queue (shuffled/original) |
| `currentIndex` | Int | Position in queue |

**State Flags:**
| Flag | Purpose |
|------|---------|
| `isStartingPlayback` | Blocks observer resync during initial start |
| `isSeeking` | Blocks time updates during manual seek |
| `currentPlaybackId` | Invalidates stale completion handlers on track change |

**Key Methods:**
| Method | Purpose |
|--------|---------|
| `play(video:from:settings:)` | Entry point - sets up queue, subscribes to EQ, calls `startPlayback()` |
| `startPlayback()` | Loads audio file, creates AVPlayerItem, waits for `.readyToPlay`, calls `prerollAndStartSynchronized()` |
| `prerollAndStartSynchronized(from:)` | Schedules audio segment, seeks video, starts both at future host time |
| `seek(to:)` | Frame-accurate seek, calls `rescheduleAudioOnly()`, restores play state |
| `resyncAudio(to:force:)` | Drift correction - compares positions, reschedules if >25ms drift |
| `togglePlayPause()` | Coordinates both pipelines with host-time sync |
| `updateEQ(_:preamp:)` | Applies EQ band gains in real-time |
| `playNext()` / `playPrevious()` | Queue navigation (previous restarts if >5s in) |
| `updateShuffleState(isOn:)` | Reshuffles or reverts queue, preserves current video |

### CustomVideoPlayer

`UIViewControllerRepresentable` wrapping `AVPlayerViewController`:
- `showsPlaybackControls = false` (custom UI)
- `updatesNowPlayingInfoCenter = false` (manual control)
- `videoGravity` configurable for aspect ratios
- Provides native PiP support

### SettingsStore (Singleton: `.shared`)

| Property | Type | Storage |
|----------|------|---------|
| `eqValues` | [Double] (6) | UserDefaults JSON |
| `preampValue` | Double | UserDefaults |
| `isShuffleOn` | Bool | @AppStorage |
| `aspectRatioMode` | AspectRatioMode | @AppStorage |
| `likedVideoIds` | Set<String> | UserDefaults JSON |
| `lastContextType` | String | @AppStorage ("all"/"playlist"/"liked") |
| `lastPlaylistId` | String | @AppStorage |
| `lastVideoId` | String | @AppStorage |
| `autoplayOnAppOpen` | Bool | @AppStorage |

EQ changes observed via Combine and applied reactively to `eqNode`.

---

## A/V Synchronization

### Initial Sync (Host Time)
```
1. Schedule audio segment at target sample
2. Seek video to position
3. Calculate future host time (now + 50ms)
4. playerNode.play(at: AVAudioTime(hostTime:))
5. player.setRate(1.0, time:, atHostTime: CMClockMakeHostTimeFromSystemUnits())
```

### Drift Correction
- **Threshold**: 25ms (`syncThresholdSeconds`)
- **Triggers**: seek, external play/pause (Control Center), PiP skip, interruption end
- **NOT periodic** - event-based only to avoid audio glitches

### Sync Observers
| Observer | Trigger |
|----------|---------|
| `timeControlStatus` | External play/pause (Control Center, lock screen) |
| `timeJumpedNotification` | PiP skip buttons, system seek |
| `interruptionNotification` | Phone call, Siri |
| `routeChangeNotification` | Headphone unplug → auto-pause |

---

## Seek Handling

**User-Initiated (`seek(to:)`)**:
1. Set `isSeeking = true`
2. Capture `wasPlaying` state
3. Frame-accurate video seek (`toleranceBefore: .zero, toleranceAfter: .zero`)
4. `rescheduleAudioOnly(to:)` - stops node, schedules segment, doesn't play
5. Restore play state if was playing
6. Delay clear `isSeeking` by 200ms (protects against late timeJumped notifications)

**System-Initiated (PiP, Control Center)**:
- Detected via `timeJumpedNotification`
- Guarded by `!isSeeking && !isStartingPlayback`
- Calls `prerollAndStartSynchronized(from:)` for full resync

---

## Equalizer

**Band Configuration:**
| Index | Frequency | Filter Type |
|-------|-----------|-------------|
| 0 | 60 Hz | lowShelf |
| 1 | 150 Hz | parametric |
| 2 | 400 Hz | parametric |
| 3 | 1 kHz | parametric |
| 4 | 2.4 kHz | parametric |
| 5 | 15 kHz | highShelf |

All bands: `bandwidth = 0.5`, `bypass = false`

**Gain Calculation:**
- Band: `0.0-1.0` → `-12dB to +12dB` → `(value - 0.5) * 24`
- Preamp: `0.0-1.0` → `-15dB to +15dB` → `(preamp - 0.5) * 30`
- Final: `bandGain + preampGain`

**Format Handling:**
Audio engine reconnects per-file via `reconnectAudioNodes(with:)` to match source format.

---

## Player UI Architecture

### View Hierarchy
```
MainTabView (root)
└── .fullScreenCover → PlayerView
    ├── CustomVideoPlayer (AVPlayerViewController)
    ├── PlayerControlsOverlay (when showControls)
    │   ├── Top bar: shuffle, EQ, aspect, like, close
    │   ├── Playback controls: prev, play/pause, next
    │   └── Seek bar with scrubbing preview
    ├── EqualizerView (when showEQ)
    ├── VerticalProgressBar (brightness/volume indicators)
    └── Center toast (aspect mode, shuffle state)
```

### Controls Auto-Hide
- Timer: 3 seconds
- Cancelled during: slider drag, brightness/volume gesture
- Tap toggles controls on/off

### Gesture Zones (controls hidden)
Screen divided into thirds:
- **Left third**: brightness (vertical drag)
- **Middle third**: tap to show controls
- **Right third**: volume (vertical drag)

Gesture activation threshold: 30pt vertical movement, must be more vertical than horizontal.

### Volume Control
- `HiddenVolumeView` (offscreen `MPVolumeView`) suppresses system HUD
- `VolumeController.shared.setVolume()` manipulates hidden slider

### Aspect Ratio Modes
| Mode | Gravity | Ratio |
|------|---------|-------|
| Default | `.resizeAspect` | nil |
| Fill | `.resizeAspectFill` | nil |
| 4:3 | `.resize` | 4/3 |
| 5:4 | `.resize` | 5/4 |
| 16:9 | `.resize` | 16/9 |
| 16:10 | `.resize` | 16/10 |

---

## Background Audio & Lock Screen

**Audio Session:**
- Category: `.playback`
- Mode: `.moviePlayback`
- Activated on init

**Remote Commands (MPRemoteCommandCenter):**
| Command | Action |
|---------|--------|
| play/pause/toggle | `togglePlayPause()` |
| nextTrack | `playNext()` |
| previousTrack | `playPrevious()` |
| changePlaybackPosition | `seek(to:)` |

Skip forward/backward explicitly disabled.

**Now Playing Info:**
Updated on play, pause, seek, track change. Includes thumbnail from `ThumbnailCache`.

---

## Interruption Handling

| Event | Action |
|-------|--------|
| `.began` | `playerNode.pause()` |
| `.ended` + `.shouldResume` | Restart engine, `resyncAudio(force: true)`, resume both |
| Route change (headphone unplug) | Pause playback |

---

## Queue Management

- `originalQueue`: unmodified video list
- `queue`: current playback order (possibly shuffled)
- `currentIndex`: position in queue

**Shuffle Toggle:**
1. If enabling: shuffle `originalQueue`, move current video to index 0
2. If disabling: revert to `originalQueue`, find current video's original index

**Previous Track:**
- If `currentTime > 5`: restart current video
- Otherwise: go to previous in queue (loops to end)

---

## Playback Context Persistence

Stored in `SettingsStore`:
- `lastContextType`: "all" / "playlist" / "liked"
- `lastPlaylistId`: UUID string (if playlist)
- `lastVideoId`: video ID

Used by:
- `autoPlayLastContext()`: restores on app launch if `autoplayOnAppOpen`
- `navigateToContextAfterPlayerClose()`: returns to source view

---

## File Structure

```
Vid/
├── ViewModels/
│   └── PlayerViewModel.swift         # Core playback logic
├── Views/
│   ├── Navigation/
│   │   └── MainTabView.swift         # Root view, player overlay host
│   ├── Player/
│   │   ├── PlayerView.swift          # Full-screen player UI
│   │   ├── CustomVideoPlayer.swift   # AVPlayerViewController wrapper
│   │   ├── PlayerControlsOverlay.swift
│   │   ├── EqualizerView.swift
│   │   └── VolumeOverlay.swift       # VerticalProgressBar, VolumeController
│   ├── Library/
│   │   └── AllVideosView.swift
│   ├── Playlists/
│   │   └── PlaylistsView.swift
│   └── Shared/
│       └── AspectRatioMode.swift
├── Managers/
│   ├── SettingsStore.swift           # EQ/settings persistence
│   ├── VideoManager.swift            # Video library
│   ├── PlaylistManager.swift
│   └── ThumbnailCache.swift
└── Models/
    ├── Video.swift
    └── Playlist.swift
```
