import SwiftUI
import Combine
import AVFoundation

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
                                    .frame(width: 60, height: 45)
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
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
                    .overlay(
                        Image(systemName: "video.fill")
                            .foregroundColor(.gray)
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        Task {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 120, height: 90)

            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                await MainActor.run {
                    self.thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("Failed to generate thumbnail: \(error)")
            }
        }
    }
}
