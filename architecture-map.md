# Vid Architecture Map

## Dual-Pipeline Playback

Vid separates video and audio processing to enable real-time EQ:
- **AVPlayer** (muted): video decoding/rendering via `AVPlayerViewController`
- **AVAudioEngine**: audio with 6-band EQ → `AVAudioPlayerNode → AVAudioUnitEQ → mainMixerNode`

Both pipelines start synchronized via `mach_absolute_time` host clock.

---

## Core Components

### PlayerViewModel (Singleton: `.shared`)

> See [PlayerViewModel.swift](file:///Users/mario/Projects/iOS/Vid/Vid/ViewModels/PlayerViewModel.swift)

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

### VideoManager (Singleton: `.shared`)

> See [VideoManager.swift](file:///Users/mario/Projects/iOS/Vid/Vid/Managers/VideoManager.swift)

| Method | Purpose |
|--------|---------|
| `loadVideosFromDisk()` | Loads persisted video metadata from `videos.json` |
| `loadVideosAsync()` | Scans Documents directory for video files, updates `videos` array |
| `importFiles(_ urls:)` | Copies files from file picker to Documents, reloads library |
| `saveVideosToDisk()` | Persists video metadata (watch status, counts) |

After loading, prunes stale references via `PlaylistManager.pruneMissingVideoIds()` and `SettingsStore.pruneMissingLikes()`.

### PlaylistManager (Singleton: `.shared`)

> See [PlaylistManager.swift](file:///Users/mario/Projects/iOS/Vid/Vid/Managers/PlaylistManager.swift)

| Method | Purpose |
|--------|---------|
| `createPlaylist(name:)` | Creates new playlist |
| `addVideo(_:to:)` | Adds video ID to playlist |
| `removeVideo(_:from:)` | Removes video ID from playlist |
| `pruneMissingVideoIds(validIds:)` | Removes deleted videos from all playlists |

### SettingsStore (Singleton: `.shared`)

> See [SettingsStore.swift](file:///Users/mario/Projects/iOS/Vid/Vid/Managers/SettingsStore.swift)

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

## Data Models

> See [Models/](file:///Users/mario/Projects/iOS/Vid/Vid/Models/)

### Video
```swift
struct Video: Identifiable, Codable, Equatable, Hashable {
    var id: String { url.absoluteString }  // Derived from URL
    let name: String
    let url: URL
    let duration: TimeInterval
    let dateAdded: Date
    let fileSize: Int64
    var isWatched: Bool
    var watchCount: Int
}
```

### Playlist
```swift
struct Playlist: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var videoIds: [String]  // Stores Video.id references
}
```

### SortOption
Enum: `name`, `duration`, `recent`, `size`, `mostWatched`
Array extension provides `filtered(by:)` and `sorted(by:ascending:)`.

---

## A/V Synchronization

### Initial Sync (Host Time)
```
1. Schedule audio segment at target sample
2. Seek video to position
3. Calculate future host time (now + 50ms)
4. Start VIDEO first: player.setRate(1.0, time:, atHostTime:)
5. Start AUDIO 40ms later: playerNode.play(at: AVAudioTime(hostTime: + 40ms))
```

**Audio Delay Compensation** (`audioDelayCompensationNanos = 40ms`):
Video decode (hardware-accelerated) starts faster than audio engine output.
Audio is intentionally delayed by 40ms to maintain lip-sync.

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

## MainTabView & App Lifecycle

> See [MainTabView.swift](file:///Users/mario/Projects/iOS/Vid/Vid/Views/Navigation/MainTabView.swift)

Root view that hosts all navigation and the player full-screen cover.

**Key Methods:**
| Method | Purpose |
|--------|---------|
| `autoPlayLastContext()` | On app launch, plays random video from last context (all/playlist/liked) if `autoplayOnAppOpen` enabled |
| `navigateToContextAfterPlayerClose()` | Returns to source tab/playlist after player closes |
| `handlePlayPlaylistActivity(_:)` | Handles Siri/Shortcuts user activity |
| `donateGenericActivities()` | Registers NSUserActivity for Siri indexing |

**Playback Context Flow:**
1. User plays from Library/Playlist/Liked → context saved to `SettingsStore`
2. Player closed → `navigateToContextAfterPlayerClose()` returns to source
3. App reopened → `autoPlayLastContext()` plays random video from saved context

---

## Siri & App Intents

> See [VidIntents.swift](file:///Users/mario/Projects/iOS/Vid/Vid/VidIntents.swift)

Requires iOS 16+. Provides voice control via Shortcuts app.

**Intents:**
| Intent | Trigger Phrase |
|--------|----------------|
| `PlayPlaylistIntent` | "Play a playlist on Vid" |
| `SearchAndPlayVideoIntent` | "Search a video on Vid" |

**Entities:**
- `PlaylistEntity`: Exposes playlists to Siri parameter picker

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

> See [Views/Player/](file:///Users/mario/Projects/iOS/Vid/Vid/Views/Player/)

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

## Data Persistence

| Data | Location |
|------|----------|
| Video metadata | `Application Support/videos.json` |
| Video files | Documents directory (user-visible) |
| Playlists | UserDefaults `"saved_playlists"` |
| Settings/EQ | UserDefaults / @AppStorage |
| Liked videos | UserDefaults `"likedVideoIds"` |

---

## File Structure

```
Vid/
├── VidApp.swift                      # App entry point
├── VidIntents.swift                  # Siri/Shortcuts (iOS 16+)
├── ViewModels/
│   └── PlayerViewModel.swift         # Core playback logic
├── Views/
│   ├── Navigation/
│   │   └── MainTabView.swift         # Root view, player overlay, autoplay
│   ├── Player/
│   │   ├── PlayerView.swift          # Full-screen player UI
│   │   ├── CustomVideoPlayer.swift   # AVPlayerViewController wrapper
│   │   ├── PlayerControlsOverlay.swift
│   │   └── EqualizerView.swift
│   ├── Library/
│   │   └── AllVideosView.swift       # Video list with sort/filter
│   ├── Playlists/
│   │   └── PlaylistsView.swift       # Playlist management
│   ├── Components/                   # Reusable UI components
│   └── Shared/
│       ├── AspectRatioMode.swift
│       └── SortOption.swift
├── Managers/
│   ├── SettingsStore.swift           # EQ/settings persistence
│   ├── VideoManager.swift            # Video library
│   ├── PlaylistManager.swift
│   └── ThumbnailCache.swift
└── Models/
    ├── Video.swift
    ├── Playlist.swift
    └── SortOption.swift              # Sort enum + Array extensions
```
