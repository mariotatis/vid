import SwiftUI

/// Defines the shared focus enums used across the application for rotary knob navigation.
enum AppFocus: Hashable {
    // Main View
    case search
    case sort
    case filter
    case layout
    case videoItem(String)
    case playlistItem(UUID)
    
    // Player View
    case playerShuffle
    case playerEQ
    case playerRatio
    case playerClose
    case playerPrevious
    case playerPlayPause
    case playerNext
    case playerSlider
    
    // EQ Overlay
    case eqPreamp
    case eqBand(Int)
    case eqReset
}

/// A button style that provides high-contrast visual feedback for focus states,
/// supporting both touch and rotary knob/game controller input.
struct VidButtonStyle: ButtonStyle {
    @Environment(\.isFocused) var isFocused: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background(isFocused ? Color.blue : Color.white.opacity(0.1))
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

/// A view modifier that adds a focus ring and scale effect to any view.
struct FocusHighlight: ViewModifier {
    @Environment(\.isFocused) var isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    func vidFocusHighlight() -> some View {
        self.modifier(FocusHighlight())
    }
}
