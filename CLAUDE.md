# Vid

iOS video player with SwiftUI: playlists, 6-band EQ, shuffle, background audio, Siri.

## Critical Rules

**Singletons only** - All managers use `.shared`. Never instantiate:
- `VideoManager.shared`, `PlaylistManager.shared`, `PlayerViewModel.shared`, `SettingsStore.shared`

**Dual-pipeline sync** - Video (AVPlayer, muted) and audio (AVAudioEngine) are separate for real-time EQ. Always control both `player` and `playerNode` together. See `togglePlayPause()`, `seek(to:)`.

**URLs are volatile** - iOS sandbox changes paths on launch. Store/compare by `video.url.lastPathComponent` only.

**Playlist resolution** - Playlists store `videoIds: [String]`. Resolve via:
```swift
playlist.videoIds.compactMap { id in videoManager.videos.first { $0.id == id } }
```

## Common Tasks

| Task | Method |
|------|--------|
| Play video | `PlayerViewModel.play(video:from:settings:)` |
| Seek | `PlayerViewModel.seek(to:)` |
| Toggle shuffle | `PlayerViewModel.updateShuffleState(isOn:)` |
| Update EQ | Modify `SettingsStore.eqValues` / `preampValue` |

## Data Persistence

| Data | Location |
|------|----------|
| Video metadata | `Application Support/videos.json` |
| Video files | Documents directory |
| Playlists | UserDefaults `"saved_playlists"` |
| Settings/EQ | UserDefaults / @AppStorage |
| Liked videos | UserDefaults `"likedVideoIds"` |

## Testing

Place `.mp4`, `.mov`, `.m4v` in iOS Simulator Documents directory.

## Architecture

See @architecture-map.md for detailed component docs, A/V sync implementation, and file structure.
