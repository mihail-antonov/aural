import CryptoKit
import Foundation

/// On-disk cache of downloaded cover images (the compressed JPEG bytes, not
/// decoded pixels), capped in size with least-recently-used eviction.
///
/// Nothing is kept in memory except a running total of the cache's size.
/// Spotify's image URLs never change content (the file name is a hash), so
/// entries never go stale; they only leave when the cache is over its cap.
public actor ArtworkCache {
    /// Aural's cache: `~/Library/Caches/app.aural.Aural/artwork`, 200 MB.
    public static let shared = ArtworkCache(
        directory: URL.cachesDirectory.appending(path: "app.aural.Aural/artwork", directoryHint: .isDirectory),
        capacityBytes: 200 * 1024 * 1024
    )

    private let directory: URL
    private let capacityBytes: Int
    /// Total size of the files, computed from disk on first use. Nil until then.
    private var totalBytes: Int?

    public init(directory: URL, capacityBytes: Int) {
        self.directory = directory
        self.capacityBytes = capacityBytes
    }

    /// The cached bytes for `url`, or nil. A hit counts as a use for eviction.
    public func data(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file) else { return nil }
        // The modification date doubles as "last used" for LRU eviction.
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
        return data
    }

    public func store(_ data: Data, for url: URL) {
        let fileManager = FileManager.default
        let file = fileURL(for: url)
        var total = totalBytes ?? measure()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let previous = (try? fileManager.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            try data.write(to: file, options: .atomic)
            total += data.count - previous
        } catch {
            Log.cache.error("Could not cache an image: \(error.localizedDescription, privacy: .public)")
        }
        totalBytes = total
        if total > capacityBytes { evict() }
    }

    /// Deletes least recently used files until the cache is at 80 % of its
    /// cap, so eviction does not run again on every following store.
    private func evict() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { file -> (url: URL, used: Date, size: Int)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        let target = capacityBytes / 10 * 8
        for entry in entries.sorted(by: { $0.used < $1.used }) where total > target {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil { total -= entry.size }
        }
        totalBytes = total
        Log.cache.info("Artwork cache trimmed to \(total / 1024) KB")
    }

    private func measure() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// File name: SHA-256 of the URL, so any URL maps to a safe, fixed-length name.
    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name, directoryHint: .notDirectory)
    }
}
