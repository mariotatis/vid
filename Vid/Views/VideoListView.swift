import SwiftUI
import Combine

struct VideoListView: View {
    let videos: [Video]
    var focusedElement: FocusState<AppFocus?>.Binding
    let onDelete: ((IndexSet) -> Void)?
    let onPlay: (Video) -> Void
    
    init(videos: [Video], focusedElement: FocusState<AppFocus?>.Binding, onDelete: ((IndexSet) -> Void)?, onPlay: @escaping (Video) -> Void) {
        self.videos = videos
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
                        HStack {
                            VStack(alignment: .leading) {
                                Text(video.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(video.durationFormatted)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(focusedElement.wrappedValue == .videoItem(video.id) ? Color.blue.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                        .vidFocusHighlight()
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
