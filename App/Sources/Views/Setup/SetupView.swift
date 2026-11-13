import AppKit
import AuralCore
import SwiftUI

/// Guided first-run setup, one step per screen, in the player's window and
/// style: the tinted background is the content; the controls are plain
/// system controls (a filled accent button for the main action, text
/// buttons and links for the rest), without Liquid Glass. Progress through
/// the four steps shows at the top.
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

/// The layout every step shares: icon, title, text and the step's own
/// content, centered vertically (scrolls if it is long), and the actions
/// pinned to the bottom.
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
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
            // Content shorter than the screen sits in the middle of it.
            .defaultScrollAnchor(.center, for: .alignment)

            VStack(spacing: 10) { actions }
                .padding(.top, 12)
        }
    }
}

/// Main action of a step: the system's full-width filled button
/// (`.borderedProminent`) in the accent color. No glass in setup.
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
            // Dark text: white is hard to read on the light peach.
            .foregroundStyle(.black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.accent)
    }
}

/// A way out or a minor choice ("Cancel", "Skip for Now"): the system
/// borderless button (plain text) under the main button, as in Apple's
/// setup screens.
private struct TextAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .font(.callout)
            .tint(.white.opacity(0.75))
            .frame(height: 26)
    }
}

/// Opens a web page or System Settings: the system `Link`, in the accent
/// color, with an "opens elsewhere" arrow.
private struct LinkButton: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
            }
        }
        .font(.callout.weight(.medium))
        // `foregroundStyle`, not `tint`: the setup's white text style
        // (set on `SetupView`) would otherwise win over the tint.
        .foregroundStyle(Theme.accent)
        .help(url.host() ?? title)
    }
}

/// A plain text field for the key and the Client ID: a faint filled
/// rounded rectangle with a thin border that turns accent while typing.
/// Not glass: glass is for controls that float over content, and a glass
/// field on the setup background looked heavy and blurry.
private struct SetupField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .focused($isFocused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Theme.accent.opacity(0.8) : .white.opacity(0.15), lineWidth: 1)
        }
        .animation(Theme.hoverAnimation, value: isFocused)
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
                LinkButton(title: "Open the Download Page", url: SoloistInstaller.downloadsPageURL)
            }
        }
    }
}

// MARK: - Step 2

private struct KeyStepView: View {
    // `@Bindable` lets us bind a text field to a property of an @Observable object.
    @Bindable var setup: SetupModel

    var body: some View {
        StepLayout(
            systemImage: "key",
            title: "Add Your API Key",
            message: "Soloist needs your personal API key. Sign in with your Premium account, generate a key and paste it here."
        ) {
            LinkButton(title: "Open Spotify for Developers", url: SoloistAPIKey.dashboardURL)
            .padding(.top, 4)

            SetupField(placeholder: "Paste your API key", text: $setup.keyText, isSecure: true, onSubmit: submit)
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

    var body: some View {
        StepLayout(
            systemImage: "hifispeaker.and.appletv",
            title: "Pair with Spotify",
            message: "Open Spotify on your phone or another computer and choose **Aural** from the devices. This is needed only once."
        ) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for Spotify…").foregroundStyle(.white.opacity(0.7))
            }
            .font(.callout)
            .padding(.top, 4)

            if setup.localNetwork == .blocked {
                Text("Aural needs Local Network access so Spotify on your other devices can find it. Allow it when macOS asks, or turn on Aural in System Settings, then quit and reopen Aural.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(.orange.opacity(0.18), in: .rect(cornerRadius: 12))
            }

            if setup.showPairingHint {
                Text("Can't see Aural, or it fails to connect? Make sure the other device is on the same Wi-Fi. If Spotify shows an error, your API key may be wrong.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if setup.localNetwork == .blocked {
                LinkButton(title: "Open Local Network Settings", url: LocalNetworkAccess.settingsURL)
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

    var body: some View {
        StepLayout(
            systemImage: "music.note.list",
            title: "Connect Your Library",
            message: "For playlists, Liked Songs, albums and search, Aural uses the Spotify Web API through your own free developer app."
        ) {

            LinkButton(title: "Open Spotify for Developers", url: SpotifyAuth.dashboardURL)
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
                    .help("Copy the redirect URI")
                }
                Text("Then paste the app's **Client ID**:")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))

            SetupField(placeholder: "Client ID", text: $setup.clientIDText, onSubmit: signIn)
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
