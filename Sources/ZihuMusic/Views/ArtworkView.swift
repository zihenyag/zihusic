import AppKit
import ImageIO
import SwiftUI

struct ArtworkView: View {
    var url: URL?
    var size: CGFloat = 190
    @State private var loadedImage: NSImage?

    private var radius: CGFloat {
        min(max(size * 0.05, 8), 18)
    }

    private var cacheKey: String {
        guard let url else { return "empty-\(Int(size))" }
        return "\(url.path)#\(Int(size.rounded()))"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.quaternary)

            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.7), Color.secondary.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        )
        .task(id: cacheKey) {
            loadedImage = await ArtworkImageCache.image(for: url, size: size)
        }
    }
}

private enum ArtworkImageCache {
    static let shared = NSCache<NSString, NSImage>()

    static func image(for url: URL?, size: CGFloat) async -> NSImage? {
        guard let url else { return nil }
        let key = "\(url.path)#\(Int(size.rounded()))" as NSString
        if let cached = ArtworkImageCache.shared.object(forKey: key) {
            return cached
        }

        return await Task.detached(priority: .utility) {
            if let cached = ArtworkImageCache.shared.object(forKey: key) {
                return cached
            }

            let image = thumbnail(from: url, size: size) ?? NSImage(contentsOf: url)
            if let image {
                ArtworkImageCache.shared.setObject(image, forKey: key)
            }
            return image
        }.value
    }

    private static func thumbnail(from url: URL, size: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let maxPixels = max(96, Int((size * 2.0).rounded()))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }

        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}
