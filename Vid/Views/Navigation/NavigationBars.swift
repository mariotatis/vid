import SwiftUI
import UIKit

enum NavigationTab: String, CaseIterable {
    case library = "Library"
    case playlists = "Playlists"
}

// MARK: - Swipe Back Gesture Enabler

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

// Fixed height for TopNavigationBar (excluding safe area)
let TOP_NAV_BAR_HEIGHT: CGFloat = 52

// Unified sizing for top navigation icon buttons
private let NAV_ICON_SIDE: CGFloat = 30
private let NAV_ICON_FONT: CGFloat = 16

struct TopNavigationBar: View {
    @Binding var selectedTab: NavigationTab

    // Library toolbar actions
    var onAddVideo: (() -> Void)?
    var onToggleSearch: (() -> Void)?
    var showingSearch: Bool = false
    var videosExist: Bool = false

    // Playlist toolbar actions
    var onAddPlaylist: (() -> Void)?
    var hasPlaylistContent: Bool = false

    // Settings
    var onOpenSettings: (() -> Void)?

    // Sort menu for Library
    var sortMenuContent: (() -> AnyView)?

    // View style menu for Playlists
    var viewStyleMenuContent: (() -> AnyView)?

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Tab buttons + settings
            HStack(spacing: 8) {
                ForEach(NavigationTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                }

                Button(action: { onOpenSettings?() }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.primary)
                }
                .buttonStyle(NavButtonStyle())
            }

            Spacer()

            // Right side: Context-specific actions
            HStack(spacing: 8) {
                if selectedTab == .library {
                    libraryActions
                } else {
                    playlistActions
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: TOP_NAV_BAR_HEIGHT)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var libraryActions: some View {
        Button(action: { onAddVideo?() }) {
            Image(systemName: "plus")
                .foregroundColor(.primary)
        }
        .buttonStyle(NavButtonStyle())

        if videosExist {
            Button(action: { onToggleSearch?() }) {
                Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                    .foregroundColor(.primary)
            }
            .buttonStyle(NavButtonStyle())

            if let menuContent = sortMenuContent {
                Menu {
                    menuContent()
                } label: {
                    NavIconCircle(systemName: "ellipsis")
                }
            }
        }
    }

    @ViewBuilder
    private var playlistActions: some View {
        Button(action: { onAddPlaylist?() }) {
            Image(systemName: "plus")
                .foregroundColor(.primary)
        }
        .buttonStyle(NavButtonStyle())

        if hasPlaylistContent {
            if let menuContent = viewStyleMenuContent {
                Menu {
                    menuContent()
                } label: {
                    NavIconCircle(systemName: "ellipsis")
                }
            }
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(colorScheme == .light ? Color(UIColor.systemGray5) : Color.white.opacity(0.15))
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .light ? Color.black.opacity(0.18) : Color.white.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Nav Button Style

struct NavButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NAV_ICON_FONT, weight: .regular))
            .frame(width: NAV_ICON_SIDE, height: NAV_ICON_SIDE)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(configuration.isPressed
                          ? (colorScheme == .light ? Color(UIColor.systemGray5) : Color.white.opacity(0.2))
                          : Color.clear)
            )
            .overlay(
                Circle()
                    .stroke(Color(UIColor.separator), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Nav Icon Circle (for Menu labels)

struct NavIconCircle: View {
    let systemName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemName)
            .foregroundColor(.primary)
            .font(.system(size: NAV_ICON_FONT, weight: .regular))
            .frame(width: NAV_ICON_SIDE, height: NAV_ICON_SIDE)
            .contentShape(Circle())
            .background(Circle().fill(Color.clear))
            .overlay(
                Circle()
                    .stroke(Color(UIColor.separator), lineWidth: 1)
            )
    }
}

// MARK: - Detail Navigation Bar

struct DetailNavigationBar: View {
    let title: String
    let onBack: () -> Void
    var trailingContent: (() -> AnyView)?

    var body: some View {
        HStack(spacing: 12) {
            // Back button (circular style matching other nav icons)
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            .buttonStyle(NavButtonStyle())

            // Title
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)

            Spacer()

            // Trailing actions
            if let trailing = trailingContent {
                trailing()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: TOP_NAV_BAR_HEIGHT)
        .background(Color(UIColor.systemBackground))
    }
}

#Preview {
    VStack {
        TopNavigationBar(
            selectedTab: .constant(.library),
            videosExist: true,
            sortMenuContent: {
                AnyView(
                    Group {
                        Button("Name") {}
                        Button("Duration") {}
                    }
                )
            }
        )
        Spacer()
    }
}
