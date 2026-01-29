import SwiftUI
import AVKit

struct PlayerControlsOverlay: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var settings: SettingsStore

    @Binding var showEQ: Bool
    @Binding var showControls: Bool
    @Binding var isDraggingSlider: Bool
    @Binding var scrubbingTime: Double?
    @Binding var isAdjustingBrightness: Bool
    @Binding var isAdjustingVolume: Bool
    @Binding var brightnessValue: CGFloat
    @Binding var volumeValue: CGFloat
    @FocusState.Binding var focusedElement: AppFocus?

    var resetControlTimer: () -> Void
    var invalidateControlTimer: () -> Void
    var showCenterToast: (String) -> Void
    var cycleAspectRatio: () -> Void

    // Gesture state
    @State private var gestureStartValue: CGFloat = 0
    @State private var gestureStartY: CGFloat = 0
    @State private var gestureCommitted = false
    private let gestureActivationThreshold: CGFloat = 30

    private var isCurrentVideoLiked: Bool {
        guard let videoId = playerVM.currentVideo?.id else { return false }
        return settings.isVideoLiked(videoId)
    }

    var body: some View {
        VStack {
            GeometryReader { innerGeo in
                let isLandscape = innerGeo.size.width > innerGeo.size.height

                VStack {
                    // Top Bar Container
                    if !(showEQ && isLandscape) {
                        topBarContent
                    }

                    Spacer()

                    if showEQ {
                        EqualizerView(
                            isDraggingSlider: $isDraggingSlider,
                            onEditingChanged: { editing in
                                if !editing {
                                    resetControlTimer()
                                } else {
                                    invalidateControlTimer()
                                }
                            },
                            focusedElement: $focusedElement
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Playback Controls
                        playbackControls
                    }

                    // Bottom Bar (Slider and Time)
                    if !showEQ {
                        bottomSeekBar
                    }
                }
            }
        }
        .background(Color.black.opacity(showEQ ? 0.6 : 0.3))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                showControls = false
                showEQ = false
                invalidateControlTimer()
            }
        }
        .simultaneousGesture(brightnessVolumeGesture)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBarContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icons Bar
            HStack(spacing: 2) {
                Button(action: {
                    settings.isShuffleOn.toggle()
                    playerVM.updateShuffleState(isOn: settings.isShuffleOn)
                    showCenterToast(settings.isShuffleOn ? "Shuffle On" : "Shuffle Off")
                }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 22))
                        .padding(6)
                        .background(Color.white.opacity(0.001))
                }
                .buttonStyle(VidButtonStyle())
                .foregroundColor(settings.isShuffleOn ? .white : Color.white.opacity(0.4))
                .focused($focusedElement, equals: .playerShuffle)

                Button(action: {
                    withAnimation { showEQ.toggle() }
                    resetControlTimer()
                }) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 22))
                        .padding(6)
                        .background(Color.white.opacity(0.001))
                }
                .buttonStyle(VidButtonStyle())
                .foregroundColor(showEQ ? .blue : .white)
                .focused($focusedElement, equals: .playerEQ)

                Button(action: {
                    cycleAspectRatio()
                    resetControlTimer()
                }) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 22))
                        .padding(6)
                        .background(Color.white.opacity(0.001))
                }
                .buttonStyle(VidButtonStyle())
                .foregroundColor(.white)
                .focused($focusedElement, equals: .playerRatio)

                Button(action: {
                    if let videoId = playerVM.currentVideo?.id {
                        settings.toggleLike(for: videoId)
                        showCenterToast(settings.isVideoLiked(videoId) ? "Liked" : "Unliked")
                    }
                    resetControlTimer()
                }) {
                    Image(systemName: isCurrentVideoLiked ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .padding(6)
                        .background(Color.white.opacity(0.001))
                }
                .buttonStyle(VidButtonStyle())
                .foregroundColor(.white)
                .focused($focusedElement, equals: .playerLike)

                Spacer()

                Button(action: {
                    playerVM.stop()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .padding(6)
                        .background(Color.white.opacity(0.001))
                }
                .buttonStyle(VidButtonStyle())
                .foregroundColor(.white)
                .focused($focusedElement, equals: .playerClose)
            }

            // Video Name
            if let videoName = playerVM.currentVideo?.name {
                Text(videoName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private var playbackControls: some View {
        HStack(spacing: 5) {
            Button(action: {
                resetControlTimer()
                playerVM.playPrevious()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .padding()
                    .background(Color.white.opacity(0.001))
            }
            .buttonStyle(VidButtonStyle())
            .foregroundColor(.white)
            .focused($focusedElement, equals: .playerPrevious)

            Button(action: {
                resetControlTimer()
                playerVM.togglePlayPause()
            }) {
                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40))
                    .padding()
                    .background(Color.white.opacity(0.001))
            }
            .buttonStyle(VidButtonStyle())
            .foregroundColor(.white)
            .focused($focusedElement, equals: .playerPlayPause)

            Button(action: {
                resetControlTimer()
                playerVM.playNext()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .padding()
                    .background(Color.white.opacity(0.001))
            }
            .buttonStyle(VidButtonStyle())
            .foregroundColor(.white)
            .focused($focusedElement, equals: .playerNext)
        }
        .padding(.bottom, 35)
    }

    // MARK: - Bottom Seek Bar

    @ViewBuilder
    private var bottomSeekBar: some View {
        HStack {
            Text(formatTime(playerVM.currentTime))
                .foregroundColor(.white)
                .font(.caption)
                .monospacedDigit()

            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 4)

                Slider(value: Binding(get: {
                    scrubbingTime ?? playerVM.currentTime
                }, set: { newValue in
                    scrubbingTime = newValue
                }), in: 0...max(playerVM.duration, 1)) { editing in
                    isDraggingSlider = editing
                    if editing {
                        playerVM.isSeeking = true
                        invalidateControlTimer()
                    } else {
                        // Only commit seek if we were actually scrubbing and it was a real intentional move
                        if let st = scrubbingTime {
                            let delta = abs(st - playerVM.currentTime)
                            // If move is > 1 second, we consider it a real seek.
                            // This ignores simple taps or presses that might move the thumb micro-amounts.
                            if delta > 1.0 {
                                playerVM.seek(to: st)
                            } else {
                                // Was just a tap or press-and-hold without dragging
                                playerVM.isSeeking = false
                            }
                        }
                        scrubbingTime = nil
                        resetControlTimer()
                    }
                }
                .accentColor(.white)
            }
            .vidFocusHighlight()
            .focused($focusedElement, equals: .playerSlider)

            Text(formatTime(playerVM.duration))
                .foregroundColor(.white)
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 60)
    }

    // MARK: - Brightness/Volume Gesture

    private var brightnessVolumeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { gesture in
                // Only handle if EQ is not shown and not dragging slider
                guard !showEQ && !isDraggingSlider else { return }

                let screenWidth = UIScreen.main.bounds.width
                let screenHeight = UIScreen.main.bounds.height
                let startX = gesture.startLocation.x
                let startY = gesture.startLocation.y
                let leftThird = screenWidth / 3
                let rightThird = screenWidth * 2 / 3

                // Ignore gestures in top/bottom 1/5 of screen (where slider is)
                let topMargin = screenHeight / 5
                let bottomMargin = screenHeight * 4 / 5
                guard startY > topMargin && startY < bottomMargin else { return }

                // Check threshold before committing to brightness/volume adjustment
                if !gestureCommitted {
                    let deltaY = abs(gesture.translation.height)
                    let deltaX = abs(gesture.translation.width)

                    // Only commit if vertical movement exceeds threshold AND is more vertical than horizontal
                    guard deltaY > gestureActivationThreshold && deltaY > deltaX else { return }

                    gestureCommitted = true
                    gestureStartY = gesture.startLocation.y

                    if startX < leftThird {
                        isAdjustingBrightness = true
                        gestureStartValue = brightnessValue
                        invalidateControlTimer()
                    } else if startX > rightThird {
                        isAdjustingVolume = true
                        gestureStartValue = volumeValue
                        invalidateControlTimer()
                    }
                }

                // Apply adjustment after committed
                if gestureCommitted {
                    if isAdjustingBrightness {
                        let deltaY = gestureStartY - gesture.location.y
                        let sensitivity: CGFloat = 1.5 / screenHeight
                        let newValue = gestureStartValue + (deltaY * sensitivity)
                        brightnessValue = min(max(newValue, 0), 1)
                        UIScreen.main.brightness = brightnessValue
                    } else if isAdjustingVolume {
                        let deltaY = gestureStartY - gesture.location.y
                        let sensitivity: CGFloat = 1.5 / screenHeight
                        let newValue = gestureStartValue + (deltaY * sensitivity)
                        volumeValue = min(max(newValue, 0), 1)
                        VolumeController.shared.setVolume(Float(volumeValue))
                    }
                }
            }
            .onEnded { _ in
                gestureCommitted = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isAdjustingBrightness = false
                        isAdjustingVolume = false
                    }
                }
                resetControlTimer()
            }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let sec = Int(seconds)
        let m = sec / 60
        let s = sec % 60
        return String(format: "%d:%02d", m, s)
    }
}
