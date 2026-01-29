import SwiftUI
import MediaPlayer

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
