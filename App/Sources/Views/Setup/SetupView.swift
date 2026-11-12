import AppKit
import AuralCore
import SwiftUI

/// Guided first-run setup. One step is active at a time; finished steps show a checkmark.
struct SetupView: View {
    let setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set up Aural")
                .font(.title2.bold())

            SetupStepRow(number: 1, title: "Install Soloist", step: .install, current: setup.step) {
                InstallStepView(setup: setup)
            }
            SetupStepRow(number: 2, title: "Get your key", step: .key, current: setup.step) {
                KeyStepView(setup: setup)
            }
            SetupStepRow(number: 3, title: "Pair your phone", step: .pair, current: setup.step) {
                PairStepView(setup: setup)
            }
            SetupStepRow(number: 4, title: "Connect your library", step: .library, current: setup.step) {
                LibraryStepView(setup: setup)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 400, height: 620, alignment: .topLeading)
    }
}

/// Step header (number or checkmark) with its content shown only while active.
private struct SetupStepRow<Content: View>: View {
    let number: Int
    let title: String
    let step: SetupModel.Step
    let current: SetupModel.Step
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: step < current ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(step < current ? Color.green : (step == current ? Color.primary : Color.secondary))
            }
            .foregroundStyle(step == current ? .primary : .secondary)

            if step == current {
                content.padding(.leading, 28)
            }
        }
    }
}

// MARK: - Step 1

private struct InstallStepView: View {
    let setup: SetupModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aural plays music through Spotify Soloist, Spotify's official player. It is downloaded directly from Spotify.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if setup.isInstalling {
                ProgressView("Downloading and checking…")
                    .controlSize(.small)
            } else {
                Button("Install Soloist") { Task { await setup.install() } }
                    .buttonStyle(.borderedProminent)
            }

            if let error = setup.installError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open the Soloist download page") { openURL(SoloistInstaller.downloadsPageURL) }
                    .buttonStyle(.link)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Soloist needs your personal API key. Sign in with your Premium account, generate a key and copy it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Spotify for Developers") { openURL(SoloistAPIKey.dashboardURL) }

            SecureField("Paste your API key", text: $setup.keyText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .disabled(setup.isStartingSoloist)

            HStack {
                Button("Continue", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.keyText.isEmpty || setup.isStartingSoloist)
                if setup.isStartingSoloist { ProgressView().controlSize(.small) }
            }

            if let error = setup.keyError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let version = setup.installedVersion {
                Text("Soloist \(version.version) installed.")
                    .font(.caption).foregroundStyle(.tertiary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Open Spotify on your phone and choose **Aural** from the devices.")
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for your phone…").foregroundStyle(.secondary)
            }

            if setup.localNetwork == .blocked {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aural needs Local Network access so your phone can find it. Allow it when macOS asks, or turn on Aural in System Settings. If you change the setting there, quit and reopen Aural.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Local Network settings") { openURL(LocalNetworkAccess.settingsURL) }
                }
                .padding(10)
                .background(.orange.opacity(0.15), in: .rect(cornerRadius: 8))
            }

            if setup.showPairingHint {
                Text("Can't see Aural or it fails to connect? Make sure your phone is on the same Wi-Fi. If Spotify shows an error, your API key may be wrong.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Enter a different key") { setup.showKeyStep(error: nil) }
                    .buttonStyle(.link)
            }
        }
    }
}

// MARK: - Step 4

private struct LibraryStepView: View {
    @Bindable var setup: SetupModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To show your playlists, Liked Songs and albums and to search, Aural uses the Spotify Web API through your own free developer app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Spotify for Developers") { openURL(SpotifyAuth.dashboardURL) }

            VStack(alignment: .leading, spacing: 4) {
                Text("Create an app, tick **Web API**, and add this redirect URI:")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(SpotifyAuth.redirectURI)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                Text("Then copy the app's **Client ID**.").font(.callout)
            }

            TextField("Paste the Client ID", text: $setup.clientIDText)
                .textFieldStyle(.roundedBorder)
                .disabled(setup.isSigningIn)

            HStack {
                Button("Sign in with Spotify", action: signIn)
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.clientIDText.isEmpty || setup.isSigningIn)
                if setup.isSigningIn {
                    ProgressView().controlSize(.small)
                    Text("Finish in your browser…").font(.callout).foregroundStyle(.secondary)
                }
            }

            if let error = setup.libraryError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Skip for now") { setup.skipLibrary() }
                .buttonStyle(.link)
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
