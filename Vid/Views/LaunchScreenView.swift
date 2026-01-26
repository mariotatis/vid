import SwiftUI

struct LaunchScreenView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var bottomLogoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack {
                Spacer()

                // App logo in the middle
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 120, height: 120)
                        .shadow(color: .red.opacity(0.3), radius: 20, x: 0, y: 10)

                    Image(systemName: "play.fill")
                        .font(.system(size: 50, weight: .regular))
                        .foregroundColor(.white)
                        .offset(x: 4) // Slight offset to center visually
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                Spacer()

                // AdaptiveLogo at the bottom
                Image("AdaptiveLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .opacity(bottomLogoOpacity)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                bottomLogoOpacity = 1.0
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
