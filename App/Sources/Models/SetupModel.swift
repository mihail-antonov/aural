import AuralCore
import Foundation
import Observation
import os

/// State and actions of the guided first-run setup:
/// 1. install Soloist, 2. enter the API key, 3. pair from the Spotify app,
/// 4. connect the library (Spotify Web API login).
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
        func setupHasLibrary() -> Bool
        func setupConnectLibrary(_ credentials: WebAPICredentials)
    }

    enum Step: Int, CaseIterable, Comparable {
        case install, key, pair, library
        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var step: Step = .install

    // Step 1
    private(set) var installedVersion: SoloistVersion?
    private(set) var isInstalling = false
    private(set) var installError: String?
    /// The installed build has expired (found at launch, or Soloist exited
    /// with code 10): step 1 then reads "Update Soloist".
    private(set) var needsUpdate = false

    // Step 2
    var keyText = ""
    private(set) var keyError: String?
    private(set) var isStartingSoloist = false

    // Step 3
    private(set) var localNetwork: LocalNetworkAccess.Status = .unknown
    /// Shown when pairing takes long: the key may be wrong or the network blocked.
    private(set) var showPairingHint = false

    // Step 4
    var clientIDText = ""
    private(set) var isSigningIn = false
    private(set) var libraryError: String?

    /// True when a step was opened from the player's settings (not first run):
    /// the step then offers "Cancel" to go back to the player unchanged.
    private(set) var isChangingSettings = false

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
        needsUpdate = version?.isExpired() == true
        step = usable ? .key : .install
        return usable
    }

    /// Soloist's build expired: step 1, worded as an update.
    func showUpdateStep() {
        stopPairingWatch()
        needsUpdate = true
        installError = nil
        installedVersion = nil
        isChangingSettings = false
        step = .install
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

    /// Back to the player. The step's state (e.g. `isChangingSettings`, which
    /// decides whether "Cancel" shows) is left as it is: the step is still
    /// fading out, and changing it now would move its buttons. It is reset
    /// when setup opens again.
    private func finish() {
        delegate?.setupFinished()
    }

    /// Opens one step from the player's settings menu.
    func beginSettingsChange(_ step: Step) {
        isChangingSettings = true
        keyText = ""
        switch step {
        case .key: showKeyStep(error: nil)
        case .library: showLibraryStep(error: nil)
        case .install, .pair: break
        }
    }

    /// Back to the player without changing anything.
    func cancelSettingsChange() {
        stopPairingWatch()
        finish()
    }

    // MARK: - Step 1: install

    func install() async {
        isInstalling = true
        installError = nil
        defer { isInstalling = false }
        do {
            installedVersion = try await installer.install()
            needsUpdate = false
        } catch {
            log.error("Install failed: \(error.localizedDescription, privacy: .public)")
            installError = error.localizedDescription
            return
        }
        // After an update (or a reinstall) the stored key and pairing still
        // work: start Soloist with them instead of asking for the key again.
        guard let storedKey = try? Keychain.readPassword(service: SoloistConfiguration.apiKeyKeychainService) else {
            step = .key
            return
        }
        do {
            try await delegate?.setupStartSoloist(apiKey: storedKey)
        } catch {
            showKeyStep(error: error.localizedDescription)
            return
        }
        showPairStep(pendingKey: nil)
        // The saved pairing session usually logs in right away.
        if delegate?.setupIsLoggedIn() == true { loginSucceeded() }
    }

    /// Replaces the installed build with Spotify's latest, for an update
    /// started from the player (Soloist must be stopped first).
    func update() async throws(SoloistInstallError) {
        installedVersion = try await installer.install()
        needsUpdate = false
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
        if delegate?.setupHasLibrary() == true {
            finish()
        } else {
            showLibraryStep(error: nil)
        }
    }

    // MARK: - Step 4: library

    func showLibraryStep(error: String?) {
        stopPairingWatch()
        libraryError = error
        if clientIDText.isEmpty, let saved = WebAPICredentials.load() { clientIDText = saved.clientID }
        step = .library
    }

    /// The Web API login expired (after 6 months): the user must sign in
    /// again before the library works (no "Cancel").
    func requireLibraryLogin(error: String) {
        isChangingSettings = false
        showLibraryStep(error: error)
    }

    /// Opens the browser for the Spotify login and waits for the redirect.
    func signInToLibrary(openURL: @escaping @Sendable (URL) async -> Void) async {
        let clientID = clientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clientID.count >= 16, clientID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            libraryError = "Paste the Client ID from your app's page in the Spotify dashboard."
            return
        }
        libraryError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let tokens = try await SpotifyAuth(clientID: clientID).login(openURL: openURL)
            let credentials = WebAPICredentials(clientID: clientID, tokens: tokens)
            try credentials.save()
            delegate?.setupConnectLibrary(credentials)
            finish()
        } catch {
            log.error("Library sign-in failed: \(error.localizedDescription, privacy: .public)")
            libraryError = error.localizedDescription
        }
    }

    /// The library is optional: the player works without it.
    func skipLibrary() {
        UserDefaults.standard.set(true, forKey: Self.librarySkippedKey)
        finish()
    }

    static let librarySkippedKey = "librarySetupSkipped"

    /// Spotify refused the pairing: the key is invalid. Back to step 2.
    func loginRejected() {
        pendingKey = nil
        Task { await delegate?.setupStopSoloist() }
        showKeyStep(error: """
            Spotify rejected this API key, so Spotify could not connect to Aural. \
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
