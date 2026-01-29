import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var showBadge: Bool = true
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
    var actionIcon: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            // Icon with shadow
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundColor(Color.gray.opacity(0.6))
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)

                // Plus badge
                if showBadge {
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color.gray.opacity(0.7))
                        )
                        .offset(x: 8, y: 8)
                }
            }
            .padding(.bottom, 8)

            // Text content
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Action button
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    HStack(spacing: 8) {
                        if let actionIcon = actionIcon {
                            Image(systemName: actionIcon)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Text(actionTitle)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(white: 0.25))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
