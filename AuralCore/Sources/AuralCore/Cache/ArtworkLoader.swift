import CoreGraphics
import Foundation
import ImageIO

/// Loads cover art downscaled to the size it is shown at, so a full-size image
/// is never decoded into memory. (A capped on-disk cache is added in Stage 7.)
public enum ArtworkLoader {
    /// No URL cache: images must not pile up in memory.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    public enum LoadError: Error { case undecodable }

    /// - Parameter maxPixelSize: longest side of the result, in pixels.
    public static func load(_ url: URL, maxPixelSize: Int) async throws -> CGImage {
        let (data, _) = try await session.data(from: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw LoadError.undecodable }
        // ImageIO decodes straight to the smaller size instead of full size first.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LoadError.undecodable
        }
        return image
    }
}
