# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vid is an iOS video player app built with SwiftUI. It supports local video playback with advanced features including playlists, a 6-band equalizer, shuffle mode, background audio, lock screen controls, and Siri integration.

## Build & Run

Open [Vid.xcodeproj](Vid.xcodeproj) in Xcode and press Cmd+R to build and run. No external dependencies or package managers are used.

**Note**: If folders (Models, Views, Managers, ViewModels) are not visible in the Project Navigator, manually add them via "Add Files to 'Vid'..." with "Create groups" selected.

## Architecture

The app follows MVVM architecture with singleton managers:

### Singletons (Global State)
All major components are singletons accessed via `.shared`:
- [VideoManager.shared](Vid/Managers/VideoManager.swift) - manages video library
- [PlaylistManager.shared](Vid/Managers/PlaylistManager.swift) - manages playlists
- [PlayerViewModel.shared](Vid/ViewModels/PlayerViewModel.swift) - controls playback
- [SettingsStore.shared](Vid/Managers/SettingsStore.swift) - app settings

**Critical**: Views receive these singletons as `@StateObject` in [MainTabView.swift:4-7](Vid/Views/MainTabView.swift#L4-L7) and pass them down as parameters or `@EnvironmentObject`. Never create new instances.

### Data Models
- [Video](Vid/Models/Video.swift) - video metadata (id is `url.absoluteString`)
- [Playlist](Vid/Models/Playlist.swift) - playlist with `videoIds: [String]` referencing Video.id

### Key Views
- [MainTabView](Vid/Views/MainTabView.swift) - root view with tabs and full-screen player overlay
- [PlayerView](Vid/Views/PlayerView.swift) - full-screen video player UI
- [CustomVideoPlayer](Vid/Views/CustomVideoPlayer.swift) - AVPlayer wrapper
- [AllVideosView](Vid/Views/AllVideosView.swift) - video library
- [PlaylistsView](Vid/Views/PlaylistsView.swift) - playlist management

## Critical Implementation Details

### Dual Audio/Video Playback System
The player uses a **dual playback architecture** ([PlayerViewModel.swift:144-187](Vid/ViewModels/PlayerViewModel.swift#L144-L187)):
- **AVPlayer**: Handles video-only playback (muted via `player.isMuted = true`)
- **AVAudioEngine**: Handles audio with EQ processing through a chain: `AVAudioPlayerNode → AVAudioUnitEQ → mainMixerNode`

**Why**: This allows real-time 6-band equalizer control without affecting video playback. Both are started simultaneously and kept in sync.

**When modifying playback**:
- Always control both player and playerNode together (play, pause, seek)
- See [seek(to:)](Vid/ViewModels/PlayerViewModel.swift#L205-L227) for the synchronization pattern
- Maintain the audio session category as `.playback` with mode `.moviePlayback`

### Sandbox URL Migration
iOS changes the app's container path on every launch. Video URLs stored in persistence become invalid.

**Solution**: [VideoManager.loadVideosFromDisk()](Vid/Managers/VideoManager.swift#L59-L80) rebuilds URLs using current Documents directory:
```swift
let fileName = video.url.lastPathComponent
let newURL = documents.appendingPathComponent(fileName)
```

**When working with video persistence**: Always store and compare videos by filename, not full URL paths.

### Data Persistence Locations
- **Videos**: `Application Support/videos.json` (migrated from Documents in [migratePersistenceIfNeeded()](Vid/Managers/VideoManager.swift#L29-L47))
- **Playlists**: `UserDefaults` key "saved_playlists"
- **Settings**: `@AppStorage` and `UserDefaults`
- **Video files**: Documents directory (user-accessible via Files app)

### Siri Integration
Two integration methods for iOS version compatibility:

1. **iOS 16+**: AppIntents framework ([VidIntents.swift](Vid/VidIntents.swift))
   - `PlayPlaylistIntent` - play specific playlist
   - `SearchAndPlayVideoIntent` - search and play video
   - Requires `@available(iOS 16.0, *)` checks

2. **iOS 15 (Legacy)**: NSUserActivity donations
   - Donated in [PlayerViewModel.donatePlayPlaylistActivity()](Vid/ViewModels/PlayerViewModel.swift#L189-L203)
   - Handled in [MainTabView.handlePlayPlaylistActivity()](Vid/Views/MainTabView.swift#L42-L62)
   - Activity type: "com.vid.playPlaylist"

**Localization**: Both include Spanish phrase alternatives (check `Locale.current.identifier.contains("es")`).

### Background Audio & Lock Screen
- Audio session configured in [setupAudioSession()](Vid/ViewModels/PlayerViewModel.swift#L44-L51) with category `.playback`
- Remote controls via [MPRemoteCommandCenter](Vid/ViewModels/PlayerViewModel.swift#L285-L325)
- Now Playing metadata updated in [updateNowPlayingInfo()](Vid/ViewModels/PlayerViewModel.swift#L327-L339)

### Auto-Resume Playback
On app launch, [MainTabView.autoPlayLastContext()](Vid/Views/MainTabView.swift#L64-L85) restores the last playback context using:
- `SettingsStore.lastContextType` - "all" or "playlist"
- `SettingsStore.lastPlaylistId` - UUID string if playlist context

## Common Development Patterns

### Playing Videos
Always use `PlayerViewModel.play(video:from:settings:)` which:
1. Sets up the playback queue (original and shuffled if needed)
2. Initializes both AVPlayer (video) and AVAudioEngine (audio)
3. Shows the player overlay
4. Donates Siri activity

### Video Queue Management
- `originalQueue` - unmodified video list
- `queue` - current playback order (shuffled or original)
- `currentIndex` - position in queue
- Shuffle state can be toggled mid-playback via [updateShuffleState()](Vid/ViewModels/PlayerViewModel.swift#L341-L360)

### Equalizer Updates
EQ is reactive to SettingsStore changes ([PlayerViewModel.swift:104-107](Vid/ViewModels/PlayerViewModel.swift#L104-L107)):
```swift
settings.$eqValues.combineLatest(settings.$preampValue)
    .sink { [weak self] (eqValues, preampValue) in
        self?.updateEQ(eqValues, preamp: preampValue)
    }
```
Each of 6 bands maps 0.0-1.0 → -12dB to +12dB, plus preamp -15dB to +15dB.

### Playlist Video Resolution
Playlists store `videoIds: [String]` (Video.id). To get actual Video objects:
```swift
let resolvedVideos = playlist.videoIds.compactMap { id in
    videoManager.videos.first(where: { $0.id == id })
}
```
See examples in [MainTabView.swift:48-50](Vid/Views/MainTabView.swift#L48-L50).

## File Organization

```
Vid/
├── VidApp.swift              # App entry point
├── VidIntents.swift          # Siri/Shortcuts (iOS 16+)
├── Models/
│   ├── Video.swift           # Video data model
│   └── Playlist.swift        # Playlist data model
├── Views/
│   ├── MainTabView.swift     # Root view with tabs
│   ├── PlayerView.swift      # Full-screen player UI
│   ├── CustomVideoPlayer.swift  # AVPlayer wrapper
│   ├── AllVideosView.swift   # Video library
│   ├── PlaylistsView.swift   # Playlist list
│   ├── PlaylistDetailView.swift
│   ├── AddVideosToPlaylistView.swift
│   ├── VideoListView.swift   # Reusable video list
│   └── FocusStyles.swift     # tvOS focus effects
├── ViewModels/
│   └── PlayerViewModel.swift # Playback controller
└── Managers/
    ├── VideoManager.swift    # Video library management
    ├── PlaylistManager.swift # Playlist management
    └── SettingsStore.swift   # App settings
```

## Testing Video Files

Place video files (.mp4, .mov, .m4v) in the iOS Simulator's Documents directory. The app scans this location and creates a README.txt there on first launch.
