# CLAUDE.md

Vid is an iOS video player app with SwiftUI, featuring playlists, 6-band EQ, shuffle, background audio, and Siri integration.

## Critical Rules

### Singletons Only
All managers are singletons via `.shared`. Never create new instances:
- `VideoManager.shared` - video library
- `PlaylistManager.shared` - playlists
- `PlayerViewModel.shared` - playback control
- `SettingsStore.shared` - settings/EQ

Views receive these as `@StateObject` in MainTabView and pass via `@EnvironmentObject`.

### Dual-Pipeline Playback
Video and audio are separate pipelines for real-time EQ:
- **AVPlayer**: video only (muted)
- **AVAudioEngine**: audio with EQ chain

**When modifying playback**: Always control both `player` and `playerNode` together. See `togglePlayPause()`, `seek(to:)` for sync patterns.

### Video URLs Are Volatile
iOS sandbox changes container paths on each launch. Never persist full URL paths.
- Store/compare by `video.url.lastPathComponent` (filename)
- `VideoManager.loadVideosFromDisk()` rebuilds URLs on load

### Playlist Video Resolution
Playlists store `videoIds: [String]`. Resolve to Video objects:
```swift
playlist.videoIds.compactMap { id in
    videoManager.videos.first { $0.id == id }
}
```

## Common Tasks

| Task | Method |
|------|--------|
| Play video | `PlayerViewModel.play(video:from:settings:)` |
| Seek | `PlayerViewModel.seek(to:)` |
| Toggle shuffle | `PlayerViewModel.updateShuffleState(isOn:)` |
| Update EQ | Modify `SettingsStore.eqValues` / `preampValue` (reactive) |

## Data Persistence

| Data | Location |
|------|----------|
| Video metadata | `Application Support/videos.json` |
| Video files | Documents directory (user-visible) |
| Playlists | UserDefaults `"saved_playlists"` |
| Settings/EQ | UserDefaults / @AppStorage |
| Liked videos | UserDefaults `"likedVideoIds"` |

## Testing

Place `.mp4`, `.mov`, `.m4v` files in iOS Simulator's Documents directory.

For detailed technical architecture, see @architecture-map.md