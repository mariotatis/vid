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
                                .font(.headline)
                                .lineLimit(1)
                            Text(video.durationFormatted)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: onDelete)
        }
    }
}
