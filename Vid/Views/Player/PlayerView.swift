import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var settings: SettingsStore

    @State private var showControls = true
    @State private var showEQ = false
    @State private var controlHideTimer: Timer?
    @State private var isDraggingSlider = false
    @FocusState private var focusedElement: AppFocus?

    @State private var centerToastMessage: String?
    @State private var scrubbingTime: Double? = nil

    // Brightness/Volume gesture states
    @State private var isAdjustingBrightness = false
    @State private var isAdjustingVolume = false
    @State private var brightnessValue: CGFloat = UIScreen.main.brightness
    @State private var volumeValue: CGFloat = 0.5
    @State private var gestureStartValue: CGFloat = 0
    @State private var gestureStartY: CGFloat = 0
    @State private var gestureCommitted = false
    private let gestureActivationThreshold: CGFloat = 30

    private var brightnessIcon: String {
        if brightnessValue > 0.66 { return "sun.max.fill" }
        if brightnessValue > 0.33 { return "sun.min.fill" }
        return "sun.min"
    }

    private var volumeIcon: String {
        if volumeValue == 0 { return "speaker.slash.fill" }
        if volumeValue > 0.66 { return "speaker.wave.3.fill" }
        if volumeValue > 0.33 { return "speaker.wave.2.fill" }
        return "speaker.wave.1.fill"
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // Hidden volume view to suppress system HUD
            HiddenVolumeView()
                .frame(width: 0, height: 0)

            // Custom Video Player with brightness/volume gesture zones
            videoPlayerContent

            // Controls Overlay
            if showControls {
                PlayerControlsOverlay(
                    showEQ: $showEQ,
                    showControls: $showControls,
                    isDraggingSlider: $isDraggingSlider,
                    scrubbingTime: $scrubbingTime,
                    isAdjustingBrightness: $isAdjustingBrightness,
                    isAdjustingVolume: $isAdjustingVolume,
                    brightnessValue: $brightnessValue,
                    volumeValue: $volumeValue,
                    focusedElement: $focusedElement,
                    resetControlTimer: resetControlTimer,
                    invalidateControlTimer: { controlHideTimer?.invalidate() },
                    showCenterToast: showCenterToast,
                    cycleAspectRatio: cycleAspectRatio
                )
            }

            // Brightness/Volume Progress Bar Overlays
            if isAdjustingBrightness {
                VerticalProgressBar(
                    value: brightnessValue,
                    icon: brightnessIcon,
                    isLeft: true
                )
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }

            if isAdjustingVolume {
                VerticalProgressBar(
                    value: volumeValue,
                    icon: volumeIcon,
                    isLeft: false
                )
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }

            // Center Toast Overlay (for aspect ratio and shuffle)
            if let message = centerToastMessage {
                centerToastView(message: message)
            }
        }
        .dynamicTypeSize(.large)
        .onAppear {
            resetControlTimer()
            if focusedElement == nil {
                focusedElement = .playerPlayPause
            }
            brightnessValue = UIScreen.main.brightness
            volumeValue = getCurrentVolume()
        }
        .onDisappear {
            controlHideTimer?.invalidate()
        }
    }

    // MARK: - Video Player Content

    @ViewBuilder
    private var videoPlayerContent: some View {
        GeometryReader { geometry in
            let ratio = settings.aspectRatioMode.ratioValue

            ZStack {
                CustomVideoPlayer(player: playerVM.player, videoGravity: settings.aspectRatioMode.gravity)
                    .edgesIgnoringSafeArea(.all)
                    .if(ratio != nil) { view in
                        view.aspectRatio(ratio!, contentMode: .fit)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Gesture zones for when controls are hidden (taps and drags)
                if !showControls && !showEQ {
                    gestureZones(geometry: geometry)
                }
            }
        }
    }

    // MARK: - Gesture Zones (Controls Hidden)

    @ViewBuilder
    private func gestureZones(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left zone - Brightness + tap to show controls
            Color.clear
                .contentShape(Rectangle())
                .gesture(brightnessGesture(geometry: geometry))
                .onTapGesture { toggleControls() }
                .frame(width: geometry.size.width / 3)

            // Middle zone - tap to show controls
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
                .frame(width: geometry.size.width / 3)

            // Right zone - Volume + tap to show controls
            Color.clear
                .contentShape(Rectangle())
                .gesture(volumeGesture(geometry: geometry))
                .onTapGesture { toggleControls() }
                .frame(width: geometry.size.width / 3)
        }
    }

    // MARK: - Brightness Gesture

    private func brightnessGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { gesture in
                let topMargin = geometry.size.height / 5
                let bottomMargin = geometry.size.height * 4 / 5
                guard gesture.startLocation.y > topMargin && gesture.startLocation.y < bottomMargin else { return }

                if !gestureCommitted {
                    let deltaY = abs(gesture.translation.height)
                    let deltaX = abs(gesture.translation.width)

                    if deltaY > gestureActivationThreshold && deltaY > deltaX {
                        gestureCommitted = true
                        isAdjustingBrightness = true
                        gestureStartValue = brightnessValue
                        gestureStartY = gesture.startLocation.y
                    }
                }

                if gestureCommitted && isAdjustingBrightness {
                    let deltaY = gestureStartY - gesture.location.y
                    let sensitivity: CGFloat = 1.5 / geometry.size.height
                    let newValue = gestureStartValue + (deltaY * sensitivity)
                    brightnessValue = min(max(newValue, 0), 1)
                    UIScreen.main.brightness = brightnessValue
                }
            }
            .onEnded { _ in
                gestureCommitted = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isAdjustingBrightness = false
                    }
                }
            }
    }

    // MARK: - Volume Gesture

    private func volumeGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { gesture in
                let topMargin = geometry.size.height / 5
                let bottomMargin = geometry.size.height * 4 / 5
                guard gesture.startLocation.y > topMargin && gesture.startLocation.y < bottomMargin else { return }

                if !gestureCommitted {
                    let deltaY = abs(gesture.translation.height)
                    let deltaX = abs(gesture.translation.width)

                    if deltaY > gestureActivationThreshold && deltaY > deltaX {
                        gestureCommitted = true
                        isAdjustingVolume = true
                        gestureStartValue = volumeValue
                        gestureStartY = gesture.startLocation.y
                    }
                }

                if gestureCommitted && isAdjustingVolume {
                    let deltaY = gestureStartY - gesture.location.y
                    let sensitivity: CGFloat = 1.5 / geometry.size.height
                    let newValue = gestureStartValue + (deltaY * sensitivity)
                    volumeValue = min(max(newValue, 0), 1)
                    VolumeController.shared.setVolume(Float(volumeValue))
                }
            }
            .onEnded { _ in
                gestureCommitted = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isAdjustingVolume = false
                    }
                }
            }
    }

    // MARK: - Center Toast

    @ViewBuilder
    private func centerToastView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 60)
                .background(Color.black.opacity(0.001))
                .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 0)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
                .transition(.scale.combined(with: .opacity))
            Spacer()
                .frame(height: 180)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helper Functions

    private func resetControlTimer() {
        controlHideTimer?.invalidate()

        controlHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                if !isDraggingSlider && !isAdjustingBrightness && !isAdjustingVolume {
                    showControls = false
                    showEQ = false
                }
            }
        }
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.15)) {
            if showControls {
                showControls = false
                showEQ = false
                controlHideTimer?.invalidate()
            } else {
                showControls = true
                resetControlTimer()
            }
        }
    }

    private func cycleAspectRatio() {
        let all = AspectRatioMode.allCases
        if let idx = all.firstIndex(of: settings.aspectRatioMode) {
            let nextIdx = (idx + 1) % all.count
            settings.aspectRatioMode = all[nextIdx]
            showCenterToast(settings.aspectRatioMode.rawValue)
        }
    }

    private func showCenterToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            centerToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if centerToastMessage == message {
                withAnimation(.easeInOut(duration: 0.3)) {
                    centerToastMessage = nil
                }
            }
        }
    }

    private func getCurrentVolume() -> CGFloat {
        let audioSession = AVAudioSession.sharedInstance()
        return CGFloat(audioSession.outputVolume)
    }
}
