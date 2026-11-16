import Foundation
import Testing
@testable import AuralCore

struct SoloistVersionTests {
    @Test func parsesRealVersionOutput() throws {
        let output = "soloist 1.3.10.65 build 1794463304 (20261112) (g19412df6ea) (macos/aarch64)\n"
        let version = try #require(SoloistVersion(versionOutput: output))
        #expect(version.version == "1.3.10.65")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(calendar.dateComponents([.year, .month, .day], from: version.buildDate) == DateComponents(year: 2026, month: 11, day: 12))
        #expect(calendar.dateComponents([.year, .month, .day], from: version.expiryDate) == DateComponents(year: 2027, month: 2, day: 10))
    }

    @Test func expiresNinetyDaysAfterBuild() {
        let build = Date(timeIntervalSince1970: 0)
        let version = SoloistVersion(version: "1", buildDate: build)
        #expect(!version.isExpired(at: build.addingTimeInterval(89 * 86_400)))
        #expect(version.isExpired(at: build.addingTimeInterval(90 * 86_400)))
    }

    @Test func offersTheUpdateInTheLastWeek() {
        let build = Date(timeIntervalSince1970: 1_800_000_000)
        let version = SoloistVersion(version: "1.3.10.65", buildDate: build)
        #expect(!version.expiresSoon(at: build.addingTimeInterval(82 * 86_400)))
        #expect(version.expiresSoon(at: build.addingTimeInterval(83 * 86_400)))
        #expect(version.expiresSoon(at: build.addingTimeInterval(91 * 86_400)))
    }

    @Test func rejectsUnknownFormat() {
        #expect(SoloistVersion(versionOutput: "something else 1.0") == nil)
    }
}

struct SoloistAPIKeyTests {
    @Test func acceptsAndTrimsPlausibleKeys() throws {
        #expect(try SoloistAPIKey.normalize("  Abc_123def456ghi789jkl012mno345pqr6 \n") == "Abc_123def456ghi789jkl012mno345pqr6")
    }

    @Test func rejectsPasteMistakes() {
        #expect(throws: SoloistAPIKey.FormatError.empty) { try SoloistAPIKey.normalize("   ") }
        #expect(throws: SoloistAPIKey.FormatError.containsWhitespace) { try SoloistAPIKey.normalize("abcdefgh ijklmnopqrst") }
        #expect(throws: SoloistAPIKey.FormatError.unexpectedCharacters) { try SoloistAPIKey.normalize("key=\"abcdefghijklmnopqrst\"") }
        #expect(throws: SoloistAPIKey.FormatError.unexpectedLength) { try SoloistAPIKey.normalize("short_key") }
    }
}

struct SoloistOutputTests {
    @Test func recognisesLoginRejectionLine() {
        #expect(SoloistProcess.isLoginRejection("2026-11-12 13:36:58.812: login failed: make sure --api-key is valid"))
        #expect(!SoloistProcess.isLoginRejection("2026-11-12 13:04:54.168: logged in as someone"))
        #expect(!SoloistProcess.isLoginRejection("2026-11-12 13:04:17.092: waiting for login — connect to \"Aural\""))
    }

    @Test func mdnsQueryIsAValidPTRQuestion() {
        let packet = LocalNetworkAccess.mdnsQuery(for: "_a._tcp.local")
        #expect(Array(packet.prefix(12)) == [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        #expect(Array(packet.dropFirst(12)) == [2, 95, 97, 4, 95, 116, 99, 112, 5, 108, 111, 99, 97, 108, 0, 0, 12, 0, 1])
    }
}

/// Installer tests use local archives (no network). Apple's `/bin/ls` stands in
/// for a correctly signed binary that is *not* from Spotify.
struct SoloistInstallerTests {
    private let workDirectory = FileManager.default.temporaryDirectory
        .appending(path: "aural-installer-test-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// Builds `archive.tar.gz` containing `files` (name in archive → source file).
    private func makeArchive(_ files: [String: URL]) async throws -> URL {
        let staging = workDirectory.appending(path: "staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for (name, source) in files {
            try FileManager.default.copyItem(at: source, to: staging.appending(path: name))
        }
        let archive = workDirectory.appending(path: "archive.tar.gz")
        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["-czf", archive.path, "-C", staging.path] + files.keys.sorted()
        )
        #expect(result.status == 0)
        return archive
    }

    private func installer(downloadURL: URL, requirement: String = SoloistInstaller.codeRequirement) -> SoloistInstaller {
        SoloistInstaller(
            executableURL: workDirectory.appending(path: "installed/soloist"),
            downloadURL: downloadURL,
            requirement: requirement
        )
    }

    @Test func rejectsBinaryNotSignedBySpotify() async throws {
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let archive = try await makeArchive(["soloist": URL(filePath: "/bin/ls")])
        let installer = installer(downloadURL: archive)

        await #expect {
            try await installer.install()
        } throws: { error in
            if case .signatureInvalid = error as? SoloistInstallError { return true }
            return false
        }
        #expect(!FileManager.default.fileExists(atPath: installer.executableURL.path))
    }

    @Test func rejectsArchiveWithoutSoloist() async throws {
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let archive = try await makeArchive(["other": URL(filePath: "/bin/ls")])
        await #expect(throws: SoloistInstallError.unexpectedArchiveContents) {
            try await installer(downloadURL: archive).install()
        }
    }

    @Test func passesSignatureCheckWhenRequirementMatches() async throws {
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let archive = try await makeArchive(["soloist": URL(filePath: "/bin/ls")])
        // `ls` matches this requirement, so the pipeline continues to the
        // version check, where `ls --version` fails as expected.
        let installer = installer(downloadURL: archive, requirement: #"identifier "com.apple.ls" and anchor apple"#)
        await #expect(throws: SoloistInstallError.versionUnreadable) {
            try await installer.install()
        }
    }

    @Test func missingInstallHasNoVersion() async {
        #expect(await installer(downloadURL: URL(filePath: "/nonexistent")).installedVersion() == nil)
    }
}
