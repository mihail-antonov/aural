import Darwin
import Foundation
import Security

public enum SoloistInstallError: Error, Equatable {
    case downloadFailed(String)
    case extractionFailed(String)
    /// The archive did not contain a plain `soloist` executable.
    case unexpectedArchiveContents
    /// The executable is not signed by Spotify's Developer ID.
    case signatureInvalid(String)
    case versionUnreadable
    /// The downloaded build has already expired (Spotify has not published a newer one yet).
    case downloadedBuildExpired
    case installFailed(String)
}

extension SoloistInstallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason): "The download failed: \(reason)"
        case .extractionFailed(let reason): "The download could not be unpacked: \(reason)"
        case .unexpectedArchiveContents: "The download did not contain the Soloist program."
        case .signatureInvalid: "The downloaded program is not signed by Spotify, so it was not installed."
        case .versionUnreadable: "The downloaded program did not report its version."
        case .downloadedBuildExpired: "The newest Soloist build has already expired. Try again later."
        case .installFailed(let reason): "Soloist could not be installed: \(reason)"
        }
    }
}

/// Downloads Soloist from Spotify's official URL, checks it and installs it into
/// Aural's folder. Aural never bundles or mirrors Soloist.
public struct SoloistInstaller: Sendable {
    // Force unwraps: constant, valid URL literals.
    public static let officialDownloadURL = URL(string: "https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz")!
    /// Fallback when the automatic install fails.
    public static let downloadsPageURL = URL(string: "https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates")!

    /// Soloist's own designated requirement, copied from `codesign -d -r-` of
    /// the official binary: identifier, Apple-issued Developer ID certificate,
    /// and Spotify's team ID (2FNC3A47ZF).
    static let codeRequirement = """
        identifier "com.spotify.soloist" and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] \
        and certificate leaf[subject.OU] = "2FNC3A47ZF"
        """

    public let executableURL: URL
    let downloadURL: URL
    let requirement: String

    public init(executableURL: URL = SoloistConfiguration.defaultExecutableURL) {
        self.init(executableURL: executableURL, downloadURL: Self.officialDownloadURL, requirement: Self.codeRequirement)
    }

    /// Tests can use a local archive and a different requirement.
    init(executableURL: URL, downloadURL: URL, requirement: String) {
        self.executableURL = executableURL
        self.downloadURL = downloadURL
        self.requirement = requirement
    }

    /// The installed build, or nil if there is none or it fails the signature check.
    /// (Expired builds are returned; check `isExpired()`.)
    public func installedVersion() async -> SoloistVersion? {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return nil }
        do {
            try verifySignature(of: executableURL)
            return try await Self.readVersion(of: executableURL)
        } catch {
            Log.soloist.error("Installed Soloist is not usable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Downloads, verifies and installs Soloist, replacing an existing install.
    /// Call only while Aural's Soloist is not running.
    @discardableResult
    public func install() async throws(SoloistInstallError) -> SoloistVersion {
        let workDirectory = FileManager.default.temporaryDirectory
            .appending(path: "aural-soloist-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let archive = try await download(into: workDirectory)
        let candidate = try await extract(archive, into: workDirectory.appending(path: "extracted"))

        do {
            try verifySignature(of: candidate)
        } catch {
            throw .signatureInvalid(error.localizedDescription)
        }
        // The signature is verified, so the quarantine flag (set if macOS marked
        // the download) is no longer needed; removing it avoids a Gatekeeper prompt.
        removexattr(candidate.path, "com.apple.quarantine", 0)

        guard let version = try? await Self.readVersion(of: candidate) else { throw .versionUnreadable }
        guard !version.isExpired() else { throw .downloadedBuildExpired }

        try moveIntoPlace(candidate)
        Log.soloist.info("Installed Soloist \(version.version, privacy: .public)")
        return version
    }

    // MARK: - Steps

    private func download(into directory: URL) async throws(SoloistInstallError) -> URL {
        let destination = directory.appending(path: "soloist.tar.gz")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let (temporaryFile, response) = try await URLSession.shared.download(from: downloadURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw SoloistInstallError.downloadFailed("HTTP \(http.statusCode)")
            }
            try FileManager.default.moveItem(at: temporaryFile, to: destination)
        } catch let error as SoloistInstallError {
            throw error
        } catch {
            throw .downloadFailed(error.localizedDescription)
        }
        return destination
    }

    /// Unpacks with the system `tar` and accepts only a regular file named `soloist`.
    private func extract(_ archive: URL, into directory: URL) async throws(SoloistInstallError) -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // `-x` from bsdtar refuses absolute paths and `..` by default.
            let result = try await ProcessRunner.run(
                URL(filePath: "/usr/bin/tar"),
                arguments: ["-xzf", archive.path, "-C", directory.path]
            )
            guard result.status == 0 else { throw SoloistInstallError.extractionFailed(result.output) }
        } catch let error as SoloistInstallError {
            throw error
        } catch {
            throw .extractionFailed(error.localizedDescription)
        }

        let candidate = directory.appending(path: "soloist")
        let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw .unexpectedArchiveContents
        }
        return candidate
    }

    /// Checks the code signature against `requirement` using the Security framework.
    func verifySignature(of executable: URL) throws {
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(executable as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else { throw SignatureError(status: status) }

        var secRequirement: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &secRequirement)
        guard status == errSecSuccess, let secRequirement else { throw SignatureError(status: status) }

        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, secRequirement, nil)
        guard status == errSecSuccess else { throw SignatureError(status: status) }
    }

    struct SignatureError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "\(message) (\(status))"
        }
    }

    /// Runs `soloist --version`. Only call on a verified executable.
    static func readVersion(of executable: URL) async throws -> SoloistVersion {
        let result = try await ProcessRunner.run(executable, arguments: ["--version"])
        guard result.status == 0, let version = SoloistVersion(versionOutput: result.output) else {
            throw SoloistInstallError.versionUnreadable
        }
        return version
    }

    private func moveIntoPlace(_ candidate: URL) throws(SoloistInstallError) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
            if fileManager.fileExists(atPath: executableURL.path) {
                // Atomic swap: the old executable stays in place until the new one is ready.
                _ = try fileManager.replaceItemAt(executableURL, withItemAt: candidate)
            } else {
                try fileManager.moveItem(at: candidate, to: executableURL)
            }
        } catch {
            throw .installFailed(error.localizedDescription)
        }
    }
}
