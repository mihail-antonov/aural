import AuralCore
import Foundation
import Observation
import os

/// State and actions of the guided first-run setup:
/// 1. install Soloist, 2. enter the API key, 3. pair from the Spotify app.
@MainActor
@Observable
final class SetupModel {
    /// What setup needs from the app (implemented by `AppModel`).
    /// `AnyObject` lets us hold it `weak`, avoiding a reference cycle.
    @MainActor
    protocol Delegate: AnyObject {
        func setupStartSoloist(apiKey: String) async throws
        func setupStopSoloist() async
        func setupFinished()
        func setupIsLoggedIn() -> Bool
    }

    enum Step: Int, CaseIterable, Comparable {
        case install, key, pair
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var step: Step = .install

    // Step 1
    private(set) var installedVersion: SoloistVersion?
    private(set) var isInstalling = false
    private(set) var installError: String?

    // Step 2
    var keyText = ""
    private(set) var keyError: String?
    private(set) var isStartingSoloist = false

    // Step 3
    private(set) var localNetwork: LocalNetworkAccess.Status = .unknown
    /// Shown when pairing takes long: the key may be wrong or the network blocked.
    private(set) var showPairingHint = false

    @ObservationIgnored weak var delegate: Delegate?
    @ObservationIgnored private let installer: SoloistInstaller
    /// The key being tried. Saved to the Keychain only after pairing succeeds,
    /// so an invalid key is never stored.
    @ObservationIgnored private var pendingKey: String?
    @ObservationIgnored private var pairingWatch: Task<Void, Never>?

    private let log = Logger(subsystem: "app.aural", category: "setup")

    /// How long to wait for pairing before showing troubleshooting hints.
    private static let pairingHintDelay: Duration = .seconds(60)

    init(installer: SoloistInstaller) {
        self.installer = installer
    }

    // MARK: - Entry points

    /// Checks the existing install. Returns true if it is usable (signed by Spotify, not expired).
    @discardableResult
    func refreshInstalledVersion() async -> Bool {
        let version = await installer.installedVersion()
        let usable = version.map { !$0.isExpired() } ?? false
        installedVersion = usable ? version : nil
        step = usable ? .key : .install
        return usable
    }

    func showKeyStep(error: String?) {
        stopPairingWatch()
        keyError = error
        step = .key
    }

    /// Pairing step. `pendingKey` is nil when the key is already stored.
    func showPairStep(pendingKey: String?) {
        self.pendingKey = pendingKey
        step = .pair
        startPairingWatch()
    }

    // MARK: - Step 1: install

    func install() async {
        isInstalling = true
        installError = nil
        defer { isInstalling = false }
        do {
            installedVersion = try await installer.install()
            step = .key
        } catch {
            log.error("Install failed: \(error.localizedDescription, privacy: .public)")
            installError = error.localizedDescription
        }
    }

    // MARK: - Step 2: API key

    func submitKey() async {
        let key: String
        do {
            key = try SoloistAPIKey.normalize(keyText)
        } catch {
            keyError = error.localizedDescription
            return
        }
        keyError = nil
        isStartingSoloist = true
        defer { isStartingSoloist = false }

        // Ask for Local Network access before Soloist starts announcing itself.
        localNetwork = LocalNetworkAccess.check()
        do {
            try await delegate?.setupStartSoloist(apiKey: key)
        } catch {
            keyError = error.localizedDescription
            return
        }
        showPairStep(pendingKey: key)
        // The data folder may already hold a pairing session.
        if delegate?.setupIsLoggedIn() == true { loginSucceeded() }
    }

    // MARK: - Step 3: pairing

    func loginSucceeded() {
        guard step == .pair else { return }
        if let pendingKey {
            do {
                try Keychain.savePassword(pendingKey, service: SoloistConfiguration.apiKeyKeychainService)
            } catch {
                log.error("Could not save the API key: \(String(describing: error), privacy: .public)")
            }
        }
        pendingKey = nil
        keyText = ""
        stopPairingWatch()
        delegate?.setupFinished()
    }

    /// Spotify refused the pairing: the key is invalid. Back to step 2.
    func loginRejected() {
        pendingKey = nil
        Task { await delegate?.setupStopSoloist() }
        showKeyStep(error: """
            Spotify rejected this API key, so your phone could not connect. \
            Check that you copied the whole key from the Soloist page, or generate a new one.
            """)
    }

    private func startPairingWatch() {
        stopPairingWatch()
        showPairingHint = false
        let started = ContinuousClock.now
        pairingWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Re-check so the UI updates once the user allows access.
                localNetwork = LocalNetworkAccess.check()
                if ContinuousClock.now - started > Self.pairingHintDelay { showPairingHint = true }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopPairingWatch() {
        pairingWatch?.cancel()
        pairingWatch = nil
    }
}
