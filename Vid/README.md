# Vid - iOS Video Player

A simple iOS video player built with SwiftUI.

## Getting Started

Since the `.xcodeproj` file was not generated programmatically (to avoid corruption), follow these steps to run the app:

### Option A: Use Existing Project (Recommended)
1. Open `Vid.xcodeproj` in Xcode.
2. In the Project Navigator (left sidebar), check if you see the folders `Models`, `Views`, `Managers`, `ViewModels`.
   - **If NOT visible**:
     - Right-click on the `Vid` folder (the yellow folder icon inside the project).
     - Select **"Add Files to 'Vid'..."**.
     - Select the `Models`, `Views`, `Managers`, `ViewModels` folders (and `VidApp.swift` if missing) from the file system.
     - **Important**: Ensure **"Create groups"** is selected and **"Add to targets"** has `Vid` checked.
3. Select your simulator or device.
4. Press **Run (Cmd+R)**.

### Option B: Create New Project
1. create a new iOS App in Xcode named `Vid`.
2. Delete the default `ContentView.swift` and `VidApp.swift`.
3. Drag and drop all Swift files provided here into the project.
4. Build and Run.

## Features
- **All Videos**: Lists videos from a selected directory.
- **Playlists**: Create playlists and add videos.
- **Settings**: Choose a directory to scan for videos. Toggle Shuffle.
- **Player**: Full screen playback with Loop and Shuffle support.

## Usage
1. Go to **Settings** tab.
2. Tap **Select Folder** and choose a folder on your device containing video files (mp4, mov, m4v).
3. Go to **All** tab to see videos.
4. Tap a video to play.
