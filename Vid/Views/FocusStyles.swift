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
    case likedPlaylist
    
    // Player View
    case playerShuffle
    case playerEQ
    case playerRatio
    case playerLike
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
            .padding(8)
            .background(
                configuration.isPressed ? Color.gray.opacity(0.3) :
                (isFocused ? Color.blue : Color.black.opacity(0.001))
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white, lineWidth: isFocused ? 2 : 0)
            )
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
