import AppKit
import AuralCore
import SwiftUI

/// Guided first-run setup, one step per screen, in the player's window and
/// style: the tinted background is the content, and the controls are Liquid
/// Glass (a prominent glass button for the main action, glass buttons and
/// fields for the rest). Progress through the four steps shows at the top.
struct SetupView: View {
    let setup: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            StepProgress(current: setup.step)
                .padding(.top, Metrics.contentTop)

            Group {
                switch setup.step {
                case .install: InstallStepView(setup: setup)
                case .key: KeyStepView(setup: setup)
                case .pair: PairStepView(setup: setup)
                case .library: LibraryStepView(setup: setup)
                }
            }
            .frame(maxHeight: .infinity)
            .transition(.opacity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .foregroundStyle(.white)
        .animation(.smooth(duration: 0.3), value: setup.step)
    }
}

/// Four short bars: done steps in the accent color, the current one white.
private struct StepProgress: View {
    let current: SetupModel.Step

    var body: some View {
        let steps = SetupModel.Step.allCases
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                Capsule()
                    .fill(step < current ? Theme.accent : .white.opacity(step == current ? 1 : 0.2))
                    .frame(height: 4)
            }
        }
        .frame(width: 120)
        .accessibilityElement()
        .accessibilityLabel("Step \((steps.firstIndex(of: current) ?? 0) + 1) of \(steps.count)")
    }
}

/// The layout every step shares: icon, title and text at the top, the step's
/// own content in the middle (scrolls if it is long), actions at the bottom.
private struct StepLayout<Content: View, Actions: View>: View {
    let systemImage: String
    let title: String
    let message: LocalizedStringKey
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(height: 52)
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            }
            .scrollIndicators(.never)

            // Nearby glass controls are grouped, so they render and morph together.
            GlassEffectContainer {
                VStack(spacing: 10) { actions }
            }
            .padding(.top, 12)
        }
    }
}

/// Main action of a step: a full-width prominent glass button.
private struct PrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy { ProgressView().controlSize(.small) }
                Text(title).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent.opacity(0.85))
    }
}

/// A secondary action: full-width glass button.
private struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
        }
        .buttonStyle(.glass)
    }
}

/// A plain text action under the buttons ("Skip for now", "Cancel").
private struct TextAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.7))
    }
}

private struct ErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Step 1

private struct InstallStepView: View {
    let setup: SetupModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepLayout(
            systemImage: "arrow.down.circle",
            title: "Install Soloist",
            message: "Aural plays music through Spotify Soloist, Spotify's official player. It is downloaded directly from Spotify and checked before it runs."
        ) {
            if let error = setup.installError {
                ErrorText(message: error)
            }
        } actions: {
            PrimaryButton(title: setup.isInstalling ? "Downloading and checking…" : "Install Soloist", isBusy: setup.isInstalling) {
                Task { await setup.install() }
            }
            .disabled(setup.isInstalling)
            if setup.installError != nil {
                SecondaryButton(title: "Open the Download Page", systemImage: "safari") {
                    openURL(SoloistInstaller.downloadsPageURL)
                }
            }
        }
    }
}

// MARK: - Step 2

private struct KeyStepView: View {
    // `@Bindable` lets us bind a text field to a property of an @Observable object.
    @Bindable var setup: SetupModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepLayout(
            systemImage: "key",
            title: "Add Your API Key",
            message: "Soloist needs your personal API key. Sign in with your Premium account, generate a key and paste it here."
        ) {
            SecondaryButton(title: "Open Spotify for Developers", systemImage: "safari") {
                openURL(SoloistAPIKey.dashboardURL)
            }
            .padding(.top, 4)

            GlassField(placeholder: "Paste your API key", text: $setup.keyText, isSecure: true, onSubmit: submit)
                .disabled(setup.isStartingSoloist)

            if let error = setup.keyError {
                ErrorText(message: error)
            }
            if let version = setup.installedVersion {
                Text("Soloist \(version.version) installed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        } actions: {
            PrimaryButton(title: "Continue", isBusy: setup.isStartingSoloist, action: submit)
                .disabled(setup.keyText.isEmpty || setup.isStartingSoloist)
            if setup.isChangingSettings {
                TextAction(title: "Cancel") { setup.cancelSettingsChange() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(setup.isStartingSoloist)
            }
        }
    }

    private func submit() {
        Task { await setup.submitKey() }
    }
}

// MARK: - Step 3

private struct PairStepView: View {
    let setup: SetupModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepLayout(
            systemImage: "iphone.radiowaves.left.and.right",
            title: "Pair Your Phone",
            message: "Open Spotify on your phone and choose **Aural** from the devices."
        ) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for your phone…").foregroundStyle(.white.opacity(0.7))
            }
            .font(.callout)
            .padding(.top, 4)

            if setup.localNetwork == .blocked {
                Text("Aural needs Local Network access so your phone can find it. Allow it when macOS asks, or turn on Aural in System Settings, then quit and reopen Aural.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(.orange.opacity(0.18), in: .rect(cornerRadius: 12))
            }

            if setup.showPairingHint {
                Text("Can't see Aural, or it fails to connect? Make sure your phone is on the same Wi-Fi. If Spotify shows an error, your API key may be wrong.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if setup.localNetwork == .blocked {
                SecondaryButton(title: "Open Local Network Settings", systemImage: "gear") {
                    openURL(LocalNetworkAccess.settingsURL)
                }
            }
            if setup.showPairingHint {
                TextAction(title: "Enter a Different Key") { setup.showKeyStep(error: nil) }
            }
        }
    }
}

// MARK: - Step 4

private struct LibraryStepView: View {
    @Bindable var setup: SetupModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepLayout(
            systemImage: "music.note.list",
            title: "Connect Your Library",
            message: "For playlists, Liked Songs, albums and search, Aural uses the Spotify Web API through your own free developer app."
        ) {
            SecondaryButton(title: "Open Spotify for Developers", systemImage: "safari") {
                openURL(SpotifyAuth.dashboardURL)
            }
            .padding(.top, 4)

            VStack(spacing: 6) {
                Text("Create an app, tick **Web API**, and add this redirect URI:")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(SpotifyAuth.redirectURI)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle(size: 12, frame: 24))
                }
                Text("Then paste the app's **Client ID**:")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))

            GlassField(placeholder: "Client ID", text: $setup.clientIDText, onSubmit: signIn)
                .disabled(setup.isSigningIn)

            if setup.isSigningIn {
                Text("Finish signing in in your browser…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let error = setup.libraryError {
                ErrorText(message: error)
            }
        } actions: {
            PrimaryButton(title: "Sign In with Spotify", isBusy: setup.isSigningIn, action: signIn)
                .disabled(setup.clientIDText.isEmpty || setup.isSigningIn)
            if setup.isChangingSettings {
                TextAction(title: "Cancel") { setup.cancelSettingsChange() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(setup.isSigningIn)
            } else {
                TextAction(title: "Skip for Now") { setup.skipLibrary() }
            }
        }
    }

    private func signIn() {
        Task {
            await setup.signInToLibrary { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
        }
    }
}
