import SwiftUI

// Local constants for VideoListView
private let VIDEO_ROW_VERTICAL_PADDING: CGFloat = 12
private let VIDEO_ROW_HORIZONTAL_INSET: CGFloat = 16

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
                                Text("\(video.durationFormatted) - \(video.fileSizeFormatted)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if !video.isWatched {
                                Text("NEW")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, VIDEO_ROW_VERTICAL_PADDING)
                        .background(focusedElement.wrappedValue == .videoItem(video.id) ? Color.blue.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                        .vidFocusHighlight()
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: VIDEO_ROW_HORIZONTAL_INSET, bottom: 0, trailing: VIDEO_ROW_HORIZONTAL_INSET))
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
