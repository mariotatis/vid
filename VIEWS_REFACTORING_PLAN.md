# Views Folder Refactoring Plan

## Overview

Restructure `Vid/Views/` with logical groupings, minimal file count, and maximum code reuse. Maintains **iOS 15.6 compatibility** and all existing logic.

---

## New Folder Structure

```
Vid/Views/
├── Components/                    # Shared reusable components
│   ├── SearchBarView.swift        # Used by 4 views
│   ├── EmptyStateView.swift       # Used by 5 views
│   └── SortMenuBuilder.swift      # Shared sort menu logic
│
├── Player/                        # Player feature
│   ├── PlayerView.swift           # Main view (~150 lines)
│   ├── PlayerControlsOverlay.swift # Top bar + playback + bottom bar + gestures
│   ├── EqualizerView.swift        # EQ overlay with preamp + 6 bands + sliders
│   └── VolumeOverlay.swift        # Brightness/volume bars + VolumeController
│
├── Library/                       # Video library
│   ├── AllVideosView.swift
│   ├── VideoListView.swift
│   └── VideoThumbnailView.swift
│
├── Playlists/                     # Playlist feature
│   ├── PlaylistsView.swift        # Main playlists list/grid
│   ├── PlaylistDetailView.swift
│   ├── LikedVideosView.swift
│   ├── AddVideosToPlaylistView.swift
│   └── PlaylistCells.swift        # Both cell types in one file
│
├── Navigation/                    # Navigation components
│   ├── MainTabView.swift
│   └── NavigationBars.swift       # TopNavigationBar + DetailNavigationBar
│
└── Shared/                        # Utilities and styles
    ├── FocusStyles.swift          # Existing file
    ├── ViewModifiers.swift        # if modifier, ResetButtonStyle
    └── AspectRatioMode.swift
```

**Total: 18 files** (currently 12)

---

## Shared Code Consolidation

### 1. Move to Models/ folder (not Views)

**SortOption.swift** - Single enum used everywhere:
```swift
// Vid/Models/SortOption.swift
enum SortOption: String, CaseIterable {
    case name, duration, recent, size, mostWatched

    var defaultAscending: Bool {
        self == .name
    }
}

extension Array where Element == Video {
    func filtered(by searchText: String) -> [Video] { ... }
    func sorted(by option: SortOption, ascending: Bool) -> [Video] { ... }
}
```

### 2. Components/SearchBarView.swift
Replaces duplicated search bar in AllVideosView, PlaylistDetailView, LikedVideosView, AddVideosToPlaylistView.

### 3. Components/EmptyStateView.swift
Configurable empty state replacing 5 duplicated implementations:
```swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var showBadge: Bool = true
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
}
```

---

## PlayerView Decomposition

### Current: 921 lines in one file
### Target: 4 files with logical groupings

| File | Contents | ~Lines |
|------|----------|--------|
| **PlayerView.swift** | Main ZStack, state, lifecycle, helper functions | 150 |
| **PlayerControlsOverlay.swift** | Top bar (shuffle/EQ/aspect/like/close) + playback buttons + bottom slider + gesture handling | 250 |
| **EqualizerView.swift** | EQ overlay with preamp slider + 6 band sliders + reset button + VerticalSlider | 180 |
| **VolumeOverlay.swift** | VerticalProgressBar + VolumeController + HiddenVolumeView | 100 |

### PlayerView.swift (Main)
```swift
struct PlayerView: View {
    // All @State properties

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            HiddenVolumeView()

            CustomVideoPlayer(...)

            if showControls {
                PlayerControlsOverlay(
                    showEQ: $showEQ,
                    showControls: $showControls,
                    // ... bindings
                )
            }

            if showEQ {
                EqualizerView(onDismiss: { showEQ = false })
            }

            VolumeOverlay(
                isAdjustingBrightness: isAdjustingBrightness,
                isAdjustingVolume: isAdjustingVolume,
                brightnessValue: brightnessValue,
                volumeValue: volumeValue
            )

            if let message = centerToastMessage {
                PlayerToastView(message: message)
            }
        }
    }

    // Helper functions: resetControlTimer, formatTime, toggleControls, etc.
}
```

### PlayerControlsOverlay.swift
Contains everything that shows when controls are visible:
- Top bar with buttons (shuffle, EQ toggle, aspect ratio, like, close)
- Video name
- Playback controls (previous, play/pause, next)
- Bottom seek bar with time labels
- Gesture zones for brightness/volume (when controls shown)

### EqualizerView.swift
Self-contained EQ panel:
- Reset button
- Preamp slider with dB label
- 6 vertical band sliders with frequency labels
- Contains `VerticalSlider` and `NativeVerticalSlider` as private subviews

### VolumeOverlay.swift
Volume/brightness visual feedback:
- `VerticalProgressBar` struct
- `VolumeController` class
- `HiddenVolumeView` struct

---

## Playlists Simplification

### PlaylistsView.swift (~200 lines after refactor)
Keep list/grid views inline (they're simple), extract only cells.

### PlaylistCells.swift (New - ~90 lines)
Both cells in one file since they're related:
```swift
struct LikedPlaylistPreviewCell: View { ... }
struct PlaylistPreviewCell: View { ... }
```

### PlaylistDetailView.swift & LikedVideosView.swift
Update to use:
- Shared `SearchBarView`
- Shared `EmptyStateView`
- Shared `SortOption` and sorting extension

---

## Navigation Consolidation

### NavigationBars.swift
Combine into single file (they're related):
```swift
struct TopNavigationBar: View { ... }
struct DetailNavigationBar: View { ... }
struct TabButton: View { ... }
struct NavButtonStyle: ButtonStyle { ... }
struct NavIconCircle: View { ... }
```

---

## Migration Steps

### Phase 1: Shared Infrastructure
1. Create `Models/SortOption.swift` with enum + Video sorting extension
2. Create `Components/SearchBarView.swift`
3. Create `Components/EmptyStateView.swift`
4. Update all views to use shared components

### Phase 2: PlayerView Refactor
1. Create `Player/` folder
2. Extract `VolumeOverlay.swift` (simplest, no dependencies)
3. Extract `EqualizerView.swift` (self-contained)
4. Extract `PlayerControlsOverlay.swift` (largest piece)
5. Simplify `PlayerView.swift`

### Phase 3: Organize Remaining Views
1. Create `Playlists/` folder, move files
2. Extract `PlaylistCells.swift`
3. Create `Library/` folder, move files
4. Extract `VideoThumbnailView.swift` from VideoListView
5. Create `Navigation/` folder
6. Combine navigation bars into `NavigationBars.swift`
7. Create `Shared/` folder for utilities

### Phase 4: Cleanup
1. Move `AspectRatioMode` to `Shared/`
2. Move `if` view modifier to `Shared/ViewModifiers.swift`
3. Move `ResetButtonStyle` to `Shared/ViewModifiers.swift`
4. Update Xcode project groups
5. Test all functionality

---

## Files Summary

### New Files to Create (6)
| File | Purpose |
|------|---------|
| `Models/SortOption.swift` | Shared enum + sorting extension |
| `Components/SearchBarView.swift` | Reusable search bar |
| `Components/EmptyStateView.swift` | Configurable empty state |
| `Player/PlayerControlsOverlay.swift` | All player controls UI |
| `Player/EqualizerView.swift` | EQ panel with sliders |
| `Player/VolumeOverlay.swift` | Volume/brightness feedback |

### Files to Split (2)
| Original | Result |
|----------|--------|
| `VideoListView.swift` | `VideoListView.swift` + `VideoThumbnailView.swift` |
| `PlaylistsView.swift` | `PlaylistsView.swift` + `PlaylistCells.swift` |

### Files to Combine (1)
| Files | Result |
|-------|--------|
| `TopNavigationBar.swift` (already has DetailNavigationBar) | `NavigationBars.swift` (rename) |

### Files to Move Only (8)
- `MainTabView.swift` → `Navigation/`
- `AllVideosView.swift` → `Library/`
- `VideoListView.swift` → `Library/`
- `PlaylistsView.swift` → `Playlists/`
- `PlaylistDetailView.swift` → `Playlists/`
- `LikedVideosView.swift` → `Playlists/`
- `AddVideosToPlaylistView.swift` → `Playlists/`
- `FocusStyles.swift` → `Shared/`

### Files Unchanged
- `CustomVideoPlayer.swift` (already minimal - 25 lines)
- `LaunchScreenView.swift` (already minimal - 56 lines)

---

## Expected Outcome

| Metric | Before | After |
|--------|--------|-------|
| Total files | 12 | 18 |
| Largest file | 921 lines | ~250 lines |
| Code duplication | High | Eliminated |
| Folder organization | Flat | Logical groups |
| Max view body size | 450+ lines | ~100 lines |
