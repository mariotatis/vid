import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var playerVM: PlayerViewModel
    @Binding var isDraggingSlider: Bool
    var onEditingChanged: (Bool) -> Void
    @FocusState.Binding var focusedElement: AppFocus?

    // 6 Bands frequencies
    private let frequencies: [String] = ["60Hz", "150Hz", "400Hz", "1kHz", "2.4kHz", "15kHz"]

    var body: some View {
        VStack(spacing: 8) {
            // Button row: Turn Off/On
            HStack(spacing: 12) {
                Spacer()
                eqToggleButton
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
                            onEditingChanged(editing)
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
                                    onEditingChanged(editing)
                                }
                                .frame(height: 120)
                            } else {
                                VerticalSlider(value: binding(for: index)) { editing in
                                    isDraggingSlider = editing
                                    onEditingChanged(editing)
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
    private var eqToggleButton: some View {
        Button(action: {
            settings.isEQEnabled.toggle()
            playerVM.setEQEnabled(settings.isEQEnabled)
        }) {
            HStack(spacing: 8) {
                Image(systemName: settings.isEQEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(settings.isEQEnabled ? "EQ On" : "EQ Off")
                    .font(.headline)
            }
            .foregroundColor(settings.isEQEnabled ? .white : .gray)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .modifier(ResetButtonStyle())
        }
        .buttonStyle(.plain)
        .vidFocusHighlight()
        .focused($focusedElement, equals: .eqToggle)
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
