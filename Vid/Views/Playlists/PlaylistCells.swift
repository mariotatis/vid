import SwiftUI

struct LikedPlaylistPreviewCell: View {
    let likedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Heart icon instead of 4-square grid
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: 44))
                        .foregroundColor(Color.gray.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Liked")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text("\(likedCount) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PlaylistPreviewCell: View {
    let playlist: Playlist
    @ObservedObject var videoManager: VideoManager

    private var resolvedVideos: [Video] {
        playlist.videoIds.compactMap { id in
            videoManager.videos.first(where: { $0.id == id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 2x2 grid of thumbnails
            GeometryReader { geometry in
                let cellSize = geometry.size.width / 2

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        thumbnailCell(index: 0, size: cellSize)
                        thumbnailCell(index: 1, size: cellSize)
                    }
                    HStack(spacing: 0) {
                        thumbnailCell(index: 2, size: cellSize)
                        thumbnailCell(index: 3, size: cellSize)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text("\(playlist.videoIds.count) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(index: Int, size: CGFloat) -> some View {
        if index < resolvedVideos.count {
            VideoThumbnailView(videoURL: resolvedVideos[index].url, contentMode: .fill, width: size, height: size)
                .frame(width: size, height: size)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "video.fill")
                        .foregroundColor(.gray.opacity(0.5))
                        .font(.system(size: size * 0.3))
                )
        }
    }
}
