import SwiftUI
import AVKit

enum MusicType: String, CaseIterable {
    case Jazz, HipHop, Electronic
}

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
    
    // EQ State
    @State private var musicType: MusicType = .Jazz
    // 6 Bands frequencies
    let frequencies: [String] = ["60Hz", "150Hz", "400Hz", "1kHz", "2.4kHz", "15kHz"]
    
    // Aspect Ratio State
    @State private var aspectRatioMode: AspectRatioMode = .default
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Custom Video Player (Hidden Controls)
            CustomVideoPlayer(player: playerVM.player, videoGravity: aspectRatioMode.gravity)
                .edgesIgnoringSafeArea(.all)
                .aspectRatio(aspectRatioMode.ratioValue, contentMode: .fit)
                .onTapGesture {
                    withAnimation {
                        showControls.toggle()
                    }
                    if showControls {
                        resetControlTimer()
                    }
                }
            
            // Controls Overlay
            if showControls {
                VStack {
                    // Top Bar (Close Button + Shuffle + EQ Toggle + Aspect Ratio)
                    HStack(spacing: 20) {
                        Button(action: {
                            settings.isShuffleOn.toggle()
                            playerVM.updateShuffleState(isOn: settings.isShuffleOn)
                        }) {
                            Image(systemName: settings.isShuffleOn ? "shuffle.circle.fill" : "shuffle.circle")
                                .font(.system(size: 30))
                                .foregroundColor(settings.isShuffleOn ? .blue : .white)
                                .shadow(radius: 5)
                        }
                        
                        Button(action: {
                            withAnimation { showEQ.toggle() }
                            resetControlTimer()
                        }) {
                            Image(systemName: "slider.vertical.3")
                                .font(.system(size: 30))
                                .foregroundColor(showEQ ? .blue : .white)
                                .shadow(radius: 5)
                        }
                        
                        Button(action: {
                            cycleAspectRatio()
                            resetControlTimer()
                        }) {
                            Image(systemName: "aspectratio")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .shadow(radius: 5)
                        }
                        
                        // Small Toast for Ratio
                        if let message = toastMessage {
                            Text(message)
                                .font(.caption)
                                .bold()
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            playerVM.stop()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .shadow(radius: 5)
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    if showEQ {
                        EqualizerOverlay()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Playback Controls
                        HStack(spacing: 50) {
                            Button(action: {
                                resetControlTimer()
                                playerVM.playPrevious()
                            }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .shadow(radius: 5)
                            }
                            
                            Button(action: {
                                resetControlTimer()
                                playerVM.togglePlayPause()
                            }) {
                                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)
                                    .shadow(radius: 5)
                            }
                            
                            Button(action: {
                                resetControlTimer()
                                playerVM.playNext()
                            }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .shadow(radius: 5)
                            }
                        }
                        .padding(.bottom, 30)
                    }
                    
                    // Bottom Bar (Slider and Time) - Always visible unless hidden by tap
                    if !showEQ {
                        HStack {
                            Text(formatTime(playerVM.currentTime))
                                .foregroundColor(.white)
                                .font(.caption)
                                .monospacedDigit()
                            
                            Slider(value: Binding(get: {
                                playerVM.currentTime
                            }, set: { newValue in
                                playerVM.isSeeking = true
                                playerVM.currentTime = newValue
                            }), in: 0...max(playerVM.duration, 1)) { editing in
                                 isDraggingSlider = editing
                                 if !editing {
                                     playerVM.seek(to: playerVM.currentTime)
                                     playerVM.isSeeking = false
                                     resetControlTimer()
                                 } else {
                                     controlHideTimer?.invalidate()
                                 }
                            }
                            .accentColor(.white)
                            
                            Text(formatTime(playerVM.duration))
                                .foregroundColor(.white)
                                .font(.caption)
                                .monospacedDigit()
                        }
                        .padding([.horizontal, .bottom])
                    }
                }
                .background(Color.black.opacity(showEQ ? 0.6 : 0.3)) // Darker background for EQ
            }
        }
        .onAppear {
            resetControlTimer()
        }
        .onDisappear {
            controlHideTimer?.invalidate()
        }
    }
    
    // Subview for EQ to keep body cleaner
    @ViewBuilder
    func EqualizerOverlay() -> some View {
        VStack {
            Text("Equalizer")
                .foregroundColor(.white)
                .font(.headline)
            
            Picker("Preset", selection: $musicType) {
                ForEach(MusicType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: musicType) { newValue in
                withAnimation {
                    // Update settings state logic in ViewModel or here
                    // Assuming existing logic maps enum to values
                    let new = values(for: newValue)
                    settings.eqValues = new
                }
            }
            
            // Custom Vertical Sliders
            HStack(spacing: 20) {
                ForEach(0..<6) { index in
                    VStack {
                        // Slider
                        VerticalSlider(value: binding(for: index))
                            .frame(height: 120)
                        
                        Text(frequencies[index])
                            .font(.caption2)
                            .foregroundColor(.white)
                            .fixedSize()
                    }
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .padding()
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
        // If EQ is shown, don't auto-hide
        if showEQ { return }
        
        controlHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                if !isDraggingSlider {
                    showControls = false
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
    
    func values(for type: MusicType) -> [Double] {
        switch type {
        case .Jazz: return [0.4, 0.5, 0.6, 0.5, 0.4, 0.3]
        case .HipHop: return [0.8, 0.7, 0.6, 0.5, 0.6, 0.7]
        case .Electronic: return [0.7, 0.8, 0.6, 0.5, 0.7, 0.6]
        }
    }
    
    private func cycleAspectRatio() {
        let all = AspectRatioMode.allCases
        if let idx = all.firstIndex(of: aspectRatioMode) {
            let nextIdx = (idx + 1) % all.count
            aspectRatioMode = all[nextIdx]
            showToast(aspectRatioMode.rawValue)
        }
    }
    
    @State private var toastMessage: String?
    
    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

// Custom Vertical Slider Component
struct VerticalSlider: View {
    @Binding var value: Double // 0.0 to 1.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 6)
                
                // Fill Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue)
                    .frame(width: 6, height: CGFloat(value) * geo.size.height)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .offset(y: -CGFloat(value) * geo.size.height + 8)
            }
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let height = geo.size.height
                        // Calculate value from bottom up
                        let locationY = height - gesture.location.y
                        let percentage = locationY / height
                        self.value = min(max(Double(percentage), 0.0), 1.0)
                    }
            )
        }
    }
}
