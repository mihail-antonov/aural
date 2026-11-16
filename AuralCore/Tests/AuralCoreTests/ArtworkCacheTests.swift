import Foundation
import Testing
@testable import AuralCore

@Suite struct ArtworkCacheTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "aural-artwork-test-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func url(_ name: String) -> URL {
        URL(string: "https://i.scdn.co/image/\(name)")! // valid literal
    }

    private func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    @Test func storesAndReadsBack() async {
        let cache = ArtworkCache(directory: directory, capacityBytes: 1_000)
        #expect(await cache.data(for: url("a")) == nil)
        await cache.store(Data([1, 2, 3]), for: url("a"))
        #expect(await cache.data(for: url("a")) == Data([1, 2, 3]))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func evictsLeastRecentlyUsedOverCapacity() async throws {
        let cache = ArtworkCache(directory: directory, capacityBytes: 300)
        let chunk = Data(repeating: 7, count: 100)
        await cache.store(chunk, for: url("old"))
        await cache.store(chunk, for: url("used"))
        await cache.store(chunk, for: url("newer"))
        // Make the order unambiguous: file dates have limited precision.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: file.path)
        }
        _ = await cache.data(for: url("used")) // a read makes it recently used

        await cache.store(chunk, for: url("new")) // 400 > 300: trim to 240

        #expect(await cache.data(for: url("used")) != nil)
        #expect(await cache.data(for: url("new")) != nil)
        #expect(fileCount() == 2)
        try? FileManager.default.removeItem(at: directory)
    }
}
