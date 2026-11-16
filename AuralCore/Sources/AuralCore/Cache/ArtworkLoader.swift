import CoreGraphics
import Foundation
import ImageIO

/// Loads cover art downscaled to the size it is shown at, so a full-size image
/// is never decoded into memory. Downloads go through `ArtworkCache` (on disk,
/// capped), so a cover is fetched from the network only once.
public enum ArtworkLoader {
    /// No URL cache: `ArtworkCache` keeps the files, and nothing piles up in memory.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    public enum LoadError: Error {
        case undecodable
        case httpStatus(Int)
    }

    /// - Parameter maxPixelSize: longest side of the result, in pixels.
    public static func load(_ url: URL, maxPixelSize: Int, cache: ArtworkCache = .shared) async throws -> CGImage {
        if let cached = await cache.data(for: url) {
            try Task.checkCancellation()
            return try decode(cached, maxPixelSize: maxPixelSize)
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw LoadError.httpStatus(http.statusCode) }
        try Task.checkCancellation()
        let image = try decode(data, maxPixelSize: maxPixelSize)
        // Cached only once it decoded: a broken download is never kept.
        await cache.store(data, for: url)
        return image
    }

    /// Decodes straight to the smaller size. The `Data` (a few dozen KB of
    /// JPEG) is released when this returns; only the small bitmap stays.
    static func decode(_ data: Data, maxPixelSize: Int) throws -> CGImage {
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

    /// Average color of an image, for the player's tinted background.
    /// Drawing the image into a 1×1 pixel bitmap lets Core Graphics do the averaging.
    public static func averageColor(of image: CGImage) -> ArtworkColor? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return ArtworkColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}

/// A plain sRGB color (AuralCore does not use SwiftUI's `Color`).
public struct ArtworkColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}
