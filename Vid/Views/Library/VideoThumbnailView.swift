import SwiftUI
import AVFoundation
import QuickLookThumbnailing

struct VideoThumbnailView: View {
    let videoURL: URL
    var contentMode: ContentMode = .fill
    var width: CGFloat? = 60
    var height: CGFloat? = 45
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Color.gray.opacity(0.3)
                    .overlay(
                        Image(systemName: isLoading ? "hourglass" : "video.fill")
                            .foregroundColor(.gray)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        // Check cache first
        if let cached = ThumbnailCache.shared.thumbnail(for: videoURL) {
            self.thumbnail = cached
            return
        }

        // Generate if not cached
        generateThumbnail()
    }

    private func generateThumbnail() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            // Use QuickLook's thumbnail generation (same as Files app)
            let size = CGSize(width: 120, height: 90)
            let scale = await UIScreen.main.scale
            let request = QLThumbnailGenerator.Request(
                fileAt: videoURL,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )

            let generator = QLThumbnailGenerator.shared

            do {
                let representation = try await generator.generateBestRepresentation(for: request)
                let image = representation.uiImage

                await MainActor.run {
                    self.isLoading = false
                    self.thumbnail = image
                    ThumbnailCache.shared.setThumbnail(image, for: videoURL)
                }
            } catch {
                // Fallback to AVAssetImageGenerator if QuickLook fails
                await fallbackThumbnailGeneration()
            }
        }
    }

    private func fallbackThumbnailGeneration() async {
        let asset = AVAsset(url: videoURL)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 90)

        var generatedImage: UIImage?
        let timePoints: [Double] = [1.0, 2.0, 0.5, 3.0]

        for timeSeconds in timePoints {
            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)

            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                generatedImage = UIImage(cgImage: cgImage)
                break
            } catch {
                continue
            }
        }

        await MainActor.run {
            self.isLoading = false
            if let image = generatedImage {
                self.thumbnail = image
                ThumbnailCache.shared.setThumbnail(image, for: videoURL)
            }
        }
    }
}
