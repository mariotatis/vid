import SwiftUI

@main
struct VidApp: App {
    @State private var isLoading = true
    @State private var appDidLoad = false

    init() {
        // Force Documents folder creation immediately on launch
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
             print("VidApp Launch: Setting up Documents Directory at: \(documentsURL.path)")
             let readmeURL = documentsURL.appendingPathComponent("README.txt")
             if !fileManager.fileExists(atPath: readmeURL.path) {
                 let content = "Put your .mp4, .mov, .m4v video files in this folder to play them in Vid."
                 do {
                     try content.write(to: readmeURL, atomically: true, encoding: .utf8)
                     print("VidApp Launch: Successfully wrote README.txt")
                 } catch {
                     print("VidApp Launch: Failed to write README.txt: \(error)")
                 }
             }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView(onAppLoaded: {
                    appDidLoad = true
                })

                LaunchScreenView()
                    .opacity(isLoading ? 1 : 0)
                    .allowsHitTesting(isLoading)
                    .animation(.easeOut(duration: 0.3), value: isLoading)
            }
            .onChange(of: appDidLoad) { loaded in
                if loaded {
                    // Wait 2 additional seconds after app loads
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isLoading = false
                    }
                }
            }
        }
    }
}
