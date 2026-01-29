import SwiftUI

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Reset Button Style

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
