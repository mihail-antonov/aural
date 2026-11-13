import AuralCore
import SwiftUI

/// The `…` menu in the window's toolbar (top right): settings the user can
/// change (Soloist API key, Spotify app Client ID) and the versions. Drawn
/// like the player's other icons (dimmed, white on hover), without the
/// toolbar's button background.
struct MoreMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section("Settings") {
                Button("Change Soloist API Key…", systemImage: "key") { model.openAPIKeySetup() }
                Button(model.library == nil ? "Connect Your Library…" : "Change Spotify Client ID…",
                       systemImage: "person.badge.key") { model.openLibrarySetup() }
            }
            Section {
                Text("Aural \(Self.appVersion)")
                if let version = model.soloistVersion {
                    Text("Soloist \(version.version)")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        // `.button` draws the menu as a button in the ambient button style.
        .menuStyle(.button)
        .buttonStyle(IconButtonStyle(size: 15, frame: 28))
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .help("Settings")
    }

    /// `CFBundleShortVersionString`, set by `MARKETING_VERSION` in project.yml.
    private static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
}

/// Shuffle, previous, play/pause, next, repeat.
struct TransportControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let playback = model.playback
        let isPlaying = model.showsPlaying
        let hasTrack = playback.track != nil

        // Equal gaps between all five buttons. The row spans the full width,
        // so the edge icons line up with the bottom row.
        HStack(spacing: 0) {
            Button("Shuffle", systemImage: "shuffle", action: model.toggleShuffle)
                .iconActive(playback.shuffle)
                .disabled(!playback.availableActions.contains(.shuffle))
                .accessibilityValue(playback.shuffle ? "On" : "Off")
                .tooltip(playback.shuffle ? "Shuffle: on" : "Shuffle: off")
                .buttonStyle(IconButtonStyle(size: 19))
            Spacer(minLength: 0)
            Button("Previous", systemImage: "backward.end.fill", action: model.previous)
                .disabled(!hasTrack)
                .tooltip("Previous")
            Spacer(minLength: 0)

            // The system's Liquid Glass button, round and large: the main action stands out.
            Button(action: model.togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .tooltip(isPlaying ? "Pause" : "Play")
            .disabled(!hasTrack)

            Spacer(minLength: 0)
            Button("Next", systemImage: "forward.end.fill", action: model.next)
                .disabled(!hasTrack)
                .tooltip("Next")
            Spacer(minLength: 0)
            Button(repeatLabel(playback.repeatMode),
                   systemImage: playback.repeatMode == .track ? "repeat.1" : "repeat",
                   action: model.cycleRepeat)
                .iconActive(playback.repeatMode != .off)
                .disabled(!playback.availableActions.contains(.setRepeat))
                .tooltip(repeatLabel(playback.repeatMode))
                .buttonStyle(IconButtonStyle(size: 19))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(IconButtonStyle(size: 22))
    }

    private func repeatLabel(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Repeat: off"
        case .context: "Repeat: playlist or album"
        case .track: "Repeat: track"
        }
    }
}

/// Search, library, queue, volume.
struct BottomControls: View {
    @Environment(AppModel.self) private var model
    @State private var showsVolume = false

    var body: some View {
        let playback = model.playback
        HStack {
            Button("Search", systemImage: "magnifyingglass") { model.page = .search }
                .tooltip("Search")
            Spacer()
            Button("Library", systemImage: "square.stack") { model.page = .library }
                .tooltip("Library")
            Spacer()
            Button("Queue", systemImage: "list.bullet") { model.page = .queue }
                .tooltip("Queue")
            Spacer()
            Button("Volume", systemImage: volumeSymbol(playback.volume)) { showsVolume.toggle() }
                .tooltip("Volume")
                .popover(isPresented: $showsVolume, arrowEdge: .top) {
                    VolumeSlider(initial: playback.volume, onChange: model.setVolume)
                }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(IconButtonStyle(size: 18))
    }

    private func volumeSymbol(_ volume: Int) -> String {
        switch volume {
        case 0: "speaker.slash.fill"
        case 1..<34: "speaker.wave.1.fill"
        case 34..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Adds the song to Liked Songs (filled accent heart); clicking again
/// removes it. In the player's header row, where the design has its `…`.
struct LikeButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(model.showsLiked ? "Remove from Liked Songs" : "Add to Liked Songs",
               systemImage: model.showsLiked ? "heart.fill" : "heart",
               action: model.toggleLike)
            .labelStyle(.iconOnly)
            .buttonStyle(IconButtonStyle(size: 18, frame: 28))
            .iconActive(model.showsLiked)
            .disabled(model.isCurrentTrackLiked == nil)
            .tooltip(model.showsLiked ? "Remove from Liked Songs" : "Add to Liked Songs")
    }
}

/// Volume slider in a popover. While dragging, the volume is sent at most
/// every 100 ms (the latest value), so it changes live without flooding Soloist.
private struct VolumeSlider: View {
    let onChange: (Int) -> Void
    @State private var value: Double
    /// Pending send while dragging; nil when none is scheduled.
    @State private var pendingSend: Task<Void, Never>?

    init(initial: Int, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        _value = State(initialValue: Double(initial))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $value, in: 0...100) { editing in
                if !editing { send() } // exact final value on release
            }
            .frame(width: 160)
            .tint(Theme.accent)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
        .padding(14)
        .accessibilityLabel("Volume")
        .onChange(of: value) { scheduleSend() }
    }

    private func scheduleSend() {
        guard pendingSend == nil else { return } // one is already on its way
        pendingSend = Task {
            try? await Task.sleep(for: .milliseconds(100))
            send()
        }
    }

    private func send() {
        pendingSend?.cancel()
        pendingSend = nil
        onChange(Int(value.rounded()))
    }
}

/// Icon-only button without a background. The icon is dimmed white and
/// becomes fully white on hover; `.iconActive` colors it instead (accent for
/// shuffle, repeat, saved), also dimmed until hovered. It dims while pressed
/// and when disabled. The default 36 pt frame keeps small icons easy to click.
struct IconButtonStyle: ButtonStyle {
    let size: CGFloat
    var frame: CGFloat? = 36

    func makeBody(configuration: Configuration) -> some View {
        // A style cannot hold @State itself, so the body is a separate view.
        IconButtonBody(configuration: configuration, size: size, frame: frame)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let frame: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.iconActiveColor) private var activeColor
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    var body: some View {
        // With Increase Contrast, icons are always full white.
        let brightens = (isHovered && isEnabled) || contrast == .increased
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(activeColor.map { $0.opacity(brightens ? 1 : Theme.iconOpacity) } ?? (brightens ? .white : Theme.icon))
            .frame(width: frame, height: frame)
            .contentShape(.rect)
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.3)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .onHover { isHovered = $0 }
            .animation(Theme.hoverAnimation, value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension EnvironmentValues {
    /// Color of an icon button that is "on" (shuffle, repeat, saved); nil when off.
    @Entry var iconActiveColor: Color?
}

extension View {
    /// Shows an icon button as "on": colored (dimmed until hovered).
    func iconActive(_ isActive: Bool, color: Color = Theme.accent) -> some View {
        environment(\.iconActiveColor, isActive ? color : nil)
    }
}
