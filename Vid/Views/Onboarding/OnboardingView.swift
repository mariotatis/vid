import SwiftUI

struct OnboardingPage {
    let imageName: String
    let title: String
    let subtitle: String
}

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(imageName: "onboarding1", title: "Offline mode", subtitle: "Keep listening anywhere, even without signal."),
        OnboardingPage(imageName: "onboarding2", title: "Equalizer", subtitle: "Tune your sound, your way."),
        OnboardingPage(imageName: "onboarding3", title: "Playlists and autoplay", subtitle: "Hit play and let it flow.")
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Pages with parallax swipe
                GeometryReader { geometry in
                    let width = geometry.size.width
                    HStack(spacing: 0) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            OnboardingPageView(
                                page: pages[index],
                                parallaxOffset: parallaxOffset(for: index, pageWidth: width)
                            )
                            .frame(width: width)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * width + dragOffset)
                    .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: currentPage)
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onEnded { value in
                                let threshold: CGFloat = width * 0.25
                                if value.translation.width < -threshold, currentPage < pages.count - 1 {
                                    currentPage += 1
                                } else if value.translation.width > threshold, currentPage > 0 {
                                    currentPage -= 1
                                }
                            }
                    )
                }

                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.primary : Color.primary.opacity(0.25))
                            .frame(width: 8, height: 8)
                            .scaleEffect(index == currentPage ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.bottom, 32)

                // Continue button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.85)) {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }

            // Skip button
            Button {
                completeOnboarding()
            } label: {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
    }

    private func parallaxOffset(for index: Int, pageWidth: CGFloat) -> CGFloat {
        let pagePosition = CGFloat(index - currentPage) * pageWidth + dragOffset
        return pagePosition * -0.3
    }

    private func completeOnboarding() {
        SettingsStore.shared.hasCompletedOnboarding = true
        withAnimation(.easeOut(duration: 0.3)) {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Single Page

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let parallaxOffset: CGFloat

    var body: some View {
        VStack(spacing: 24) {
            onboardingImage
                .offset(x: parallaxOffset)

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private var onboardingImage: some View {
        if UIImage(named: page.imageName) != nil {
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(16)
                .padding(.horizontal, 32)
        } else {
            // Fallback placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemGray6))
                    .frame(width: 200, height: 200)

                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                    .shadow(color: .red.opacity(0.3), radius: 12, x: 0, y: 6)

                Image(systemName: "play.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundColor(.white)
                    .offset(x: 2)
            }
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
