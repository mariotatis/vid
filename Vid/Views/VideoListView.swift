import SwiftUI
import Combine
import AVFoundation
import QuickLookThumbnailing

struct VideoListView: View {
    let videos: [Video]
    let showThumbnails: Bool
    var focusedElement: FocusState<AppFocus?>.Binding
    let onDelete: ((IndexSet) -> Void)?
    let onPlay: (Video) -> Void

    init(videos: [Video], showThumbnails: Bool = true, focusedElement: FocusState<AppFocus?>.Binding, onDelete: ((IndexSet) -> Void)?, onPlay: @escaping (Video) -> Void) {
        self.videos = videos
        self.showThumbnails = showThumbnails
        self.focusedElement = focusedElement
        self.onDelete = onDelete
        self.onPlay = onPlay
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(videos) { video in
                    Button(action: {
                        onPlay(video)
                    }) {
                        HStack(spacing: 12) {
                            if showThumbnails {
                                VideoThumbnailView(videoURL: video.url)
                                    .cornerRadius(6)
                            }

                            VStack(alignment: .leading) {
                                Text(video.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                Text(video.durationFormatted)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(focusedElement.wrappedValue == .videoItem(video.id) ? Color.blue.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                        .vidFocusHighlight()
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparatorTint(Color.gray.opacity(0.3))
                    .focused(focusedElement, equals: .videoItem(video.id))
                    .id(video.id)
                }
                .onDelete(perform: onDelete)
            }
            .listStyle(.plain)
            .onChange(of: focusedElement.wrappedValue) { newValue in
                if case .videoItem(let id) = newValue {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

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
