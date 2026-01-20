import SwiftUI
import Combine

struct VideoListView: View {
    let videos: [Video]
    let onDelete: ((IndexSet) -> Void)?
    let onPlay: (Video) -> Void
    
    var body: some View {
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
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onDelete(perform: onDelete)
        }
        .listStyle(.plain)
    }
}
