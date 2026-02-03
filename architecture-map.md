# Architecture Map

Detailed technical reference for Vid. For critical rules, see @CLAUDE.md.

## Dual-Pipeline Playback

Vid separates video and audio to enable real-time EQ:
- **AVPlayer** (muted): video via `AVPlayerViewController`
- **AVAudioEngine**: `AVAudioPlayerNode → AVAudioUnitEQ → mainMixerNode`

Synchronized via `mach_absolute_time` host clock.

### A/V Sync Flow
```
1. Schedule audio segment at target sample
2. Seek video to position
3. Calculate future host time (now + 50ms)
4. Start VIDEO: player.setRate(1.0, time:, atHostTime:)
5. Start AUDIO 40ms later: playerNode.play(at: hostTime + 40ms)
```

Audio delayed 40ms (`audioDelayCompensationNanos`) to compensate for faster video decode.

### Drift Correction
- Threshold: 25ms (`syncThresholdSeconds`)
- Triggers: seek, external play/pause, PiP skip, interruption end
- Event-based only (not periodic) to avoid audio glitches

### Sync Observers
| Observer | Trigger |
|----------|---------|
| `timeControlStatus` | External play/pause (Control Center, lock screen) |
| `timeJumpedNotification` | PiP skip buttons, system seek |
| `interruptionNotification` | Phone call, Siri |
| `routeChangeNotification` | Headphone unplug → auto-pause |

---

## Core Components

### PlayerViewModel

> [PlayerViewModel.swift](Vid/ViewModels/PlayerViewModel.swift)

Split into extensions:
- [+Playback](Vid/ViewModels/PlayerViewModel+Playback.swift) - controls, shuffle, queue
- [+AudioEngine](Vid/ViewModels/PlayerViewModel+AudioEngine.swift) - setup, nodes
- [+AudioSync](Vid/ViewModels/PlayerViewModel+AudioSync.swift) - drift correction
- [+EQ](Vid/ViewModels/PlayerViewModel+EQ.swift) - band config
- [+Remote](Vid/ViewModels/PlayerViewModel+Remote.swift) - lock screen, observers

**Key Properties:**
| Name | Purpose |
|------|---------|
| `player` | AVPlayer (video only, muted) |
| `engine` / `playerNode` / `eqNode` | Audio processing chain |
| `queue` / `originalQueue` | Playback queue (shuffled/original) |
| `currentIndex` | Position in queue |

**State Flags:**
| Flag | Purpose |
|------|---------|
| `isStartingPlayback` | Blocks observer resync during initial start |
| `isSeeking` | Blocks time updates during manual seek |
| `currentPlaybackId` | Invalidates stale completion handlers |

**Key Methods:**
| Method | Purpose |
|--------|---------|
| `play(video:from:settings:)` | Entry point → `startPlayback()` |
| `startPlayback()` | Load audio, wait for `.readyToPlay`, → `prerollAndStartSynchronized()` |
| `prerollAndStartSynchronized(from:)` | Schedule audio, seek video, start both at host time |
| `seek(to:)` | Frame-accurate seek, reschedule audio |
| `resyncAudio(to:force:)` | Drift correction if >25ms |

### VideoManager

> [VideoManager.swift](Vid/Managers/VideoManager.swift)

| Method | Purpose |
|--------|---------|
| `loadVideosFromDisk()` | Load metadata from `videos.json` |
| `loadVideosAsync()` | Scan Documents for video files |
| `importFiles(_ urls:)` | Copy from file picker, reload |
| `saveVideosToDisk()` | Persist metadata |

### PlaylistManager

> [PlaylistManager.swift](Vid/Managers/PlaylistManager.swift)

| Method | Purpose |
|--------|---------|
| `createPlaylist(name:)` | Create playlist |
| `addVideo(_:to:)` / `removeVideo(_:from:)` | Modify playlist |
| `pruneMissingVideoIds(validIds:)` | Remove deleted videos |

### SettingsStore

> [SettingsStore.swift](Vid/Managers/SettingsStore.swift)

| Property | Storage |
|----------|---------|
| `eqValues` / `preampValue` | UserDefaults JSON |
| `isShuffleOn` / `aspectRatioMode` | @AppStorage |
| `likedVideoIds` | UserDefaults JSON |
| `lastContextType` / `lastPlaylistId` / `lastVideoId` | @AppStorage |

EQ changes observed via Combine, applied reactively.

---

## Data Models

### Video
```swift
struct Video: Identifiable, Codable, Equatable, Hashable {
    var id: String { url.absoluteString }
    let name: String, url: URL, duration: TimeInterval
    let dateAdded: Date, fileSize: Int64
    var isWatched: Bool, watchCount: Int
}
```

### Playlist
```swift
struct Playlist: Identifiable, Codable, Equatable {
    var id: UUID, name: String, videoIds: [String]
}
```

---

## Equalizer

| Index | Frequency | Type |
|-------|-----------|------|
| 0 | 60 Hz | lowShelf |
| 1 | 150 Hz | parametric |
| 2 | 400 Hz | parametric |
| 3 | 1 kHz | parametric |
| 4 | 2.4 kHz | parametric |
| 5 | 15 kHz | highShelf |

**Gain Calculation:**
- Band: `(value - 0.5) * 24` → -12dB to +12dB
- Preamp: `(preamp - 0.5) * 30` → -15dB to +15dB

---

## Player UI

> [Views/Player/](Vid/Views/Player/)

```
MainTabView
└── .fullScreenCover → PlayerView
    ├── CustomVideoPlayer (AVPlayerViewController)
    ├── PlayerControlsOverlay
    ├── EqualizerView
    └── VerticalProgressBar (brightness/volume)
```

**Gestures (controls hidden):**
- Left third: brightness
- Middle: tap to show controls
- Right third: volume

---

## Background Audio

**Audio Session:** `.playback` / `.moviePlayback`

**Remote Commands:**
| Command | Action |
|---------|--------|
| play/pause/toggle | `togglePlayPause()` |
| nextTrack/previousTrack | `playNext()` / `playPrevious()` |
| changePlaybackPosition | `seek(to:)` |

---

## Siri Intents

> [VidIntents.swift](Vid/VidIntents.swift) (iOS 16+)

| Intent | Phrase |
|--------|--------|
| `PlayPlaylistIntent` | "Play a playlist on Vid" |
| `SearchAndPlayVideoIntent` | "Search a video on Vid" |

---

## Data Persistence

| Data | Location |
|------|----------|
| Video metadata | `Application Support/videos.json` |
| Video files | Documents directory |
| Playlists | UserDefaults `"saved_playlists"` |
| Settings/EQ | UserDefaults / @AppStorage |
| Liked videos | UserDefaults `"likedVideoIds"` |

---

## File Structure

```
Vid/
├── VidApp.swift
├── VidIntents.swift
├── ViewModels/
│   ├── PlayerViewModel.swift
│   └── PlayerViewModel+{Playback,AudioEngine,AudioSync,EQ,Remote}.swift
├── Views/
│   ├── Navigation/MainTabView.swift
│   ├── Player/{PlayerView,CustomVideoPlayer,PlayerControlsOverlay,EqualizerView}.swift
│   ├── Library/AllVideosView.swift
│   └── Playlists/PlaylistsView.swift
├── Managers/{SettingsStore,VideoManager,PlaylistManager,ThumbnailCache}.swift
└── Models/{Video,Playlist,SortOption}.swift
```
