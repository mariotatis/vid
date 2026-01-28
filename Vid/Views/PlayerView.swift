import SwiftUI
import AVKit
import MediaPlayer

enum AspectRatioMode: String, CaseIterable {
    case `default` = "Default"
    case fill = "Fill"
    case ratio4_3 = "4:3"
    case ratio5_4 = "5:4"
    case ratio16_9 = "16:9"
    case ratio16_10 = "16:10"
    
    var gravity: AVLayerVideoGravity {
        switch self {
        case .default: return .resizeAspect
        case .fill: return .resizeAspectFill
        default: return .resize // Stretch
        }
    }
    
    var ratioValue: CGFloat? {
        switch self {
        case .ratio4_3: return 4/3
        case .ratio5_4: return 5/4
        case .ratio16_9: return 16/9
        case .ratio16_10: return 16/10
        default: return nil
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @EnvironmentObject var settings: SettingsStore
    
    @State private var showControls = true
    @State private var showEQ = false
    @State private var controlHideTimer: Timer?
    @State private var isDraggingSlider = false
    @FocusState private var focusedElement: AppFocus?

    // 6 Bands frequencies
    let frequencies: [String] = ["60Hz", "150Hz", "400Hz", "1kHz", "2.4kHz", "15kHz"]

    @State private var centerToastMessage: String?

    // Brightness/Volume gesture states
    @State private var isAdjustingBrightness = false
    @State private var isAdjustingVolume = false
    @State private var brightnessValue: CGFloat = UIScreen.main.brightness
    @State private var volumeValue: CGFloat = 0.5
    @State private var gestureStartValue: CGFloat = 0
    @State private var gestureStartY: CGFloat = 0

    private var isCurrentVideoLiked: Bool {
        guard let videoId = playerVM.currentVideo?.id else { return false }
        return settings.isVideoLiked(videoId)
    }

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
                        HStack(spacing: 0) {
                            // Left zone - Brightness + tap to show controls
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { gesture in
                                            // Ignore gestures in top/bottom 1/5 of screen
                                            let topMargin = geometry.size.height / 5
                                            let bottomMargin = geometry.size.height * 4 / 5
                                            guard gesture.startLocation.y > topMargin && gesture.startLocation.y < bottomMargin else { return }

                                            if !isAdjustingBrightness {
                                                isAdjustingBrightness = true
                                                gestureStartValue = brightnessValue
                                                gestureStartY = gesture.startLocation.y
                                            }
                                            let deltaY = gestureStartY - gesture.location.y
                                            let sensitivity: CGFloat = 1.5 / geometry.size.height
                                            let newValue = gestureStartValue + (deltaY * sensitivity)
                                            brightnessValue = min(max(newValue, 0), 1)
                                            UIScreen.main.brightness = brightnessValue
                                        }
                                        .onEnded { _ in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                withAnimation(.easeOut(duration: 0.3)) {
                                                    isAdjustingBrightness = false
                                                }
                                            }
                                        }
                                )
                                .onTapGesture {
                                    toggleControls()
                                }
                                .frame(width: geometry.size.width / 3)

                            // Middle zone - tap to show controls
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleControls()
                                }
                                .frame(width: geometry.size.width / 3)

                            // Right zone - Volume + tap to show controls
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { gesture in
                                            // Ignore gestures in top/bottom 1/5 of screen
                                            let topMargin = geometry.size.height / 5
                                            let bottomMargin = geometry.size.height * 4 / 5
                                            guard gesture.startLocation.y > topMargin && gesture.startLocation.y < bottomMargin else { return }

                                            if !isAdjustingVolume {
                                                isAdjustingVolume = true
                                                gestureStartValue = volumeValue
                                                gestureStartY = gesture.startLocation.y
                                            }
                                            let deltaY = gestureStartY - gesture.location.y
                                            let sensitivity: CGFloat = 1.5 / geometry.size.height
                                            let newValue = gestureStartValue + (deltaY * sensitivity)
                                            volumeValue = min(max(newValue, 0), 1)
                                            setSystemVolume(Float(volumeValue))
                                        }
                                        .onEnded { _ in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                withAnimation(.easeOut(duration: 0.3)) {
                                                    isAdjustingVolume = false
                                                }
                                            }
                                        }
                                )
                                .onTapGesture {
                                    toggleControls()
                                }
                                .frame(width: geometry.size.width / 3)
                        }
                    }
                }
            }
            
            // Controls Overlay
            if showControls {
                VStack {
                    GeometryReader { innerGeo in
                        let isLandscape = innerGeo.size.width > innerGeo.size.height
                        
                        VStack {
                            // Top Bar Container
                            if !(showEQ && isLandscape) {
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
                            
                            Spacer()
                            
                            if showEQ {
                                EqualizerOverlay()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                // Playback Controls
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
                            
                            // Bottom Bar (Slider and Time)
                            if !showEQ {
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
                                            playerVM.currentTime
                                        }, set: { newValue in
                                            playerVM.isSeeking = true
                                            playerVM.currentTime = newValue
                                        }), in: 0...max(playerVM.duration, 1)) { editing in
                                             isDraggingSlider = editing
                                             if !editing {
                                                 playerVM.seek(to: playerVM.currentTime)
                                                 resetControlTimer()
                                             } else {
                                                 controlHideTimer?.invalidate()
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
                        }
                    }
                }
                .background(Color.black.opacity(showEQ ? 0.6 : 0.3))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showControls = false
                        showEQ = false
                        controlHideTimer?.invalidate()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { gesture in
                            // Only handle if EQ is not shown
                            guard !showEQ else { return }

                            let screenWidth = UIScreen.main.bounds.width
                            let screenHeight = UIScreen.main.bounds.height
                            let startX = gesture.startLocation.x
                            let startY = gesture.startLocation.y
                            let leftThird = screenWidth / 3
                            let rightThird = screenWidth * 2 / 3

                            // Ignore gestures in top/bottom 1/5 of screen
                            let topMargin = screenHeight / 5
                            let bottomMargin = screenHeight * 4 / 5
                            guard startY > topMargin && startY < bottomMargin else { return }

                            if startX < leftThird {
                                // Brightness
                                if !isAdjustingBrightness && !isAdjustingVolume {
                                    isAdjustingBrightness = true
                                    gestureStartValue = brightnessValue
                                    gestureStartY = gesture.startLocation.y
                                    controlHideTimer?.invalidate()
                                }
                                if isAdjustingBrightness {
                                    let deltaY = gestureStartY - gesture.location.y
                                    let sensitivity: CGFloat = 1.5 / screenHeight
                                    let newValue = gestureStartValue + (deltaY * sensitivity)
                                    brightnessValue = min(max(newValue, 0), 1)
                                    UIScreen.main.brightness = brightnessValue
                                }
                            } else if startX > rightThird {
                                // Volume
                                if !isAdjustingVolume && !isAdjustingBrightness {
                                    isAdjustingVolume = true
                                    gestureStartValue = volumeValue
                                    gestureStartY = gesture.startLocation.y
                                    controlHideTimer?.invalidate()
                                }
                                if isAdjustingVolume {
                                    let deltaY = gestureStartY - gesture.location.y
                                    let sensitivity: CGFloat = 1.5 / screenHeight
                                    let newValue = gestureStartValue + (deltaY * sensitivity)
                                    volumeValue = min(max(newValue, 0), 1)
                                    setSystemVolume(Float(volumeValue))
                                }
                            }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isAdjustingBrightness = false
                                    isAdjustingVolume = false
                                }
                            }
                            resetControlTimer()
                        }
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

    @ViewBuilder
    func EqualizerOverlay() -> some View {
        VStack(spacing: 8) {
            // Reset button on top, aligned right
            HStack {
                Spacer()
                resetEQButton
            }
            .padding(.horizontal)

            // Equalizer content
            VStack(spacing: 15) {
                Spacer()
                    .frame(height: 15)

                // Preamp Slider
                VStack(spacing: 4) {
                    HStack {
                        Text("Preamp")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        let db = (settings.preampValue - 0.5) * 30
                        Text(String(format: "%+.1f dB", db))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)

                    ZStack {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.6))
                            .frame(height: 4)
                            .padding(.horizontal)

                        Slider(value: $settings.preampValue, in: 0...1) { editing in
                            isDraggingSlider = editing
                            if !editing {
                                resetControlTimer()
                            } else {
                                controlHideTimer?.invalidate()
                            }
                        }
                        .accentColor(.white)
                        .padding(.horizontal)
                    }
                    .vidFocusHighlight()
                    .focused($focusedElement, equals: .eqPreamp)
                }

                // Custom Vertical Sliders
                HStack(spacing: 20) {
                    ForEach(0..<6) { index in
                        VStack {
                            if #available(iOS 16.0, *) {
                               NativeVerticalSlider(value: binding(for: index)) { editing in
                                   isDraggingSlider = editing
                                   if !editing {
                                       resetControlTimer()
                                   } else {
                                       controlHideTimer?.invalidate()
                                   }
                               }
                               .frame(height: 120)
                            } else {
                               VerticalSlider(value: binding(for: index)) { editing in
                                   isDraggingSlider = editing
                                   if !editing {
                                       resetControlTimer()
                                   } else {
                                       controlHideTimer?.invalidate()
                                   }
                               }
                               .frame(height: 120)
                            }

                            Text(frequencies[index])
                                .font(.caption2)
                                .foregroundColor(.white)
                                .fixedSize()
                        }
                        .vidFocusHighlight()
                        .focused($focusedElement, equals: .eqBand(index))
                    }
                }
                .padding()

                Spacer()
                    .frame(height: 10)
            }
            .background(Color.black.opacity(0.7))
            .cornerRadius(20)
        }
        .padding()
        .onTapGesture {
            // Swallows taps to prevent closing the EQ when tapping on the background
        }
    }

    @ViewBuilder
    private var resetEQButton: some View {
        Button(action: {
            settings.eqValues = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
            settings.preampValue = 0.5
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                Text("Reset EQ")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .modifier(ResetButtonStyle())
        }
        .buttonStyle(.plain)
        .vidFocusHighlight()
        .focused($focusedElement, equals: .eqReset)
    }
    
    private func binding(for index: Int) -> Binding<Double> {
        return Binding(
            get: {
                if index < settings.eqValues.count {
                    return settings.eqValues[index]
                }
                return 0.5
            },
            set: { val in
                if index < settings.eqValues.count {
                    settings.eqValues[index] = val
                }
            }
        )
    }
    
    private func resetControlTimer() {
        controlHideTimer?.invalidate()

        controlHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                // Don't hide if dragging slider or adjusting brightness/volume
                if !isDraggingSlider && !isAdjustingBrightness && !isAdjustingVolume {
                    showControls = false
                    showEQ = false
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let sec = Int(seconds)
        let m = sec / 60
        let s = sec % 60
        return String(format: "%d:%02d", m, s)
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

    private func setSystemVolume(_ volume: Float) {
        VolumeController.shared.setVolume(volume)
    }

    private func getCurrentVolume() -> CGFloat {
        let audioSession = AVAudioSession.sharedInstance()
        return CGFloat(audioSession.outputVolume)
    }
}

struct VerticalSlider: View {
    @Binding var value: Double // 0.0 to 1.0
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6)

                // Fill Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 6, height: CGFloat(value) * geo.size.height)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .offset(y: -CGFloat(value) * geo.size.height + 14)
            }
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onEditingChanged(true)
                        let height = geo.size.height
                        let locationY = height - gesture.location.y
                        let percentage = locationY / height
                        self.value = min(max(Double(percentage), 0.0), 1.0)
                    }
                    .onEnded { _ in
                        onEditingChanged(false)
                    }
            )
        }
    }
}

struct NativeVerticalSlider: View {
    @Binding var value: Double // 0.0 to 1.0
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
                .accentColor(.white)
                .tint(.white)
                .rotationEffect(.degrees(-90))
                .frame(width: geo.size.height, height: geo.size.width)
                .offset(x: -geo.size.height / 2 + geo.size.width / 2,
                        y: geo.size.height / 2 - geo.size.width / 2)
        }
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct ResetButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.white.opacity(0.1)))
                .cornerRadius(12)
        } else {
            content
                .background(Color(white: 0.25))
                .cornerRadius(12)
        }
    }
}

struct VerticalProgressBar: View {
    let value: CGFloat // 0.0 to 1.0
    let icon: String
    let isLeft: Bool

    var body: some View {
        HStack {
            if !isLeft { Spacer() }

            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(height: 24)

                ZStack(alignment: .bottom) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 6, height: 120)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 6, height: 120 * value)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )

            if isLeft { Spacer() }
        }
        .padding(.horizontal, 50)
    }
}

// Hidden MPVolumeView to suppress system volume HUD and provide volume control
class VolumeController {
    static let shared = VolumeController()
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?

    func setup() -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 100, height: 100))
        view.showsVolumeSlider = true
        self.volumeView = view

        // Find slider after a brief delay to ensure it's loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.volumeSlider = self?.findSlider(in: view)
        }
        return view
    }

    private func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider {
            return slider
        }
        for subview in view.subviews {
            if let slider = findSlider(in: subview) {
                return slider
            }
        }
        return nil
    }

    func setVolume(_ value: Float) {
        // Try cached slider first
        if let slider = volumeSlider {
            slider.value = value
            return
        }
        // Fallback: find slider again
        if let view = volumeView, let slider = findSlider(in: view) {
            volumeSlider = slider
            slider.value = value
        }
    }
}

struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        VolumeController.shared.setup()
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
