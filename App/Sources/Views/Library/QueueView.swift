import AuralCore
import SwiftUI

/// The Queue page: the song playing and what comes next, grouped like
/// Spotify ("Next in Queue", "Up Next", "Autoplay"). When Aural is playing
/// one of its lists (Liked Songs, a playlist's tracks, search results), the
/// upcoming songs can be clicked to jump there. Soloist's own playlist /
/// album queue has no "play this entry" command, so those rows only show.
struct QueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let queue = model.queue
        List {
            if let track = model.playback.track {
                SwiftUI.Section {
                    QueueRow(track: track, isCurrent: true).libraryRow()
                } header: {
                    ListSectionHeader(title: "Now Playing")
                }
            }
            ForEach(Self.sections(queue.upNext)) { section in
                SwiftUI.Section {
                    ForEach(section.entries) { entry in
                        row(entry, canJump: queue.canJump).libraryRow()
                    }
                } header: {
                    ListSectionHeader(title: section.title)
                }
            }
            // Something plays but nothing follows: say so under it.
            if model.playback.track != nil, queue.upNext.isEmpty {
                EmptyState(
                    title: "Nothing Queued", systemImage: "list.bullet",
                    message: "When the music ends, Spotify keeps playing similar songs."
                )
                .view
                .libraryRow()
            }
        }
        .libraryList()
        .libraryRowHeight(LibraryRowHeight.track)
        // Nothing at all: centered on the page.
        .emptyState(
            EmptyState(title: "Nothing Playing", systemImage: "play.circle",
                       message: "Play a song, playlist or album to see what comes next."),
            when: model.playback.track == nil && queue.upNext.isEmpty
        )
    }

    @ViewBuilder
    private func row(_ entry: QueueEntry, canJump: Bool) -> some View {
        if canJump {
            Button { model.jump(to: entry) } label: { QueueRow(track: entry.track) }
                .buttonStyle(.plain)
                .help("Play now")
        } else {
            QueueRow(track: entry.track)
        }
    }

    struct Section: Identifiable {
        let id: Int
        let title: String
        let entries: [QueueEntry]
    }

    /// Runs of entries with the same kind of source, in queue order.
    static func sections(_ entries: [QueueEntry]) -> [Section] {
        var sections: [Section] = []
        var current: [QueueEntry] = []
        func close() {
            guard let first = current.first else { return }
            sections.append(Section(id: sections.count, title: title(for: first.source), entries: current))
            current = []
        }
        for entry in entries {
            if let last = current.last, title(for: last.source) != title(for: entry.source) { close() }
            current.append(entry)
        }
        close()
        return sections
    }

    private static func title(for source: QueueEntry.Source) -> String {
        switch source {
        case .queue: "Next in Queue"
        case .list, .context: "Up Next"
        case .autoplay: "Autoplay"
        }
    }
}
