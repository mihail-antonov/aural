import AuralCore
import SwiftUI

/// The Library page: playlists, Liked Songs and saved albums.
struct LibraryPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        RequiresLibrary { library in
            LibraryContent(library: library, model: model)
        }
    }
}

/// The Queue page, opened with the player's queue button. The queue comes
/// from Soloist, so it works without the Web API.
struct QueuePage: View {
    @Environment(AppModel.self) private var model
    @State private var path: [BrowseDestination] = []

    var body: some View {
        BrowseStack(title: "Queue", path: $path, model: model) {
            Button("Clear Queue", systemImage: "trash", action: model.clearQueue)
                .labelStyle(.iconOnly)
                .buttonStyle(IconButtonStyle(size: 14, frame: 28))
                .disabled(!model.queue.canClear)
                .tooltip("Clear queue")
        } root: {
            QueueView()
        }
    }
}

/// The Search page, opened with the player's search button.
struct SearchPage: View {
    @Environment(AppModel.self) private var model
    @State private var path: [BrowseDestination] = []

    var body: some View {
        RequiresLibrary { _ in
            BrowseStack(title: "Search", path: $path, model: model) {
                SearchView(model: model)
            }
        }
    }
}

/// Shows `content` when the Web API is connected, otherwise a way to connect it.
private struct RequiresLibrary<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: (LibraryService) -> Content

    var body: some View {
        if let library = model.library {
            content(library)
                // A new identity per connection resets all loaded lists.
                .id(ObjectIdentifier(library))
        } else {
            ContentUnavailableView {
                Label("Library not connected", systemImage: "music.note.list")
            } description: {
                Text("Connect your Spotify library to see playlists, Liked Songs and albums, and to search.")
            } actions: {
                Button("Connect your library") { model.openLibrarySetup() }
            }
        }
    }
}

/// A page opened inside the library or search.
enum BrowseDestination: Hashable {
    case playlist(PlaylistSummary)
    case album(AlbumSummary)
    case artist(ArtistSummary)
}

/// Identity of a page in `BrowseStack`'s stack.
private struct PageKey: Hashable, Identifiable {
    let index: Int
    let destination: BrowseDestination
    var id: Self { self }
}

/// Items that open a page when clicked.
protocol Browsable: Identifiable where ID: Hashable {
    var destination: BrowseDestination { get }
}

extension PlaylistSummary: Browsable { var destination: BrowseDestination { .playlist(self) } }
extension AlbumSummary: Browsable { var destination: BrowseDestination { .album(self) } }
extension ArtistSummary: Browsable { var destination: BrowseDestination { .artist(self) } }

/// A page header and a stack of playlist / album / artist pages. Pages slide
/// in from the right and back out to the right (cross-fade with Reduce
/// Motion). Going back is the header's chevron (or Esc), which returns to
/// the player from the top level. `accessory` stays visible above every page.
///
/// Aural draws its own stack: macOS 27's `NavigationStack` did not slide
/// pages in from the right and back out to the right like iOS.
struct BrowseStack<Accessory: View, Trailing: View, Root: View>: View {
    let title: String
    @Binding var path: [BrowseDestination]
    let model: AppModel
    /// When this changes (e.g. the library tab), the pages are replaced
    /// without animation, so the old ones never slide over the new content.
    var resetID: AnyHashable?
    @ViewBuilder let accessory: () -> Accessory
    /// Buttons at the right end of the header (e.g. the queue's "Clear").
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let root: () -> Root

    init(
        title: String, path: Binding<[BrowseDestination]>, model: AppModel, resetID: AnyHashable? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.title = title
        _path = path
        self.model = model
        self.resetID = resetID
        self.accessory = accessory
        self.trailing = trailing
        self.root = root
    }
    /// The row opened last: marked as selected when coming back to the list.
    @State private var openedID: AnyHashable?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var push: Animation { .smooth(duration: 0.3) }

    var body: some View {
        ZStack {
            // The list stays alive (keeping its scroll position and loaded
            // pages) while a page covers it.
            root()
                .opacity(path.isEmpty ? 1 : 0)
                .allowsHitTesting(path.isEmpty)
                .accessibilityHidden(!path.isEmpty)
            // Identified by position *and* page: going back and opening
            // another playlist must count as a new page (so it slides in),
            // not as the leaving page with new content.
            ForEach(path.indices.map { PageKey(index: $0, destination: path[$0]) }) { key in
                let isTop = key.index == path.count - 1
                page(for: key.destination)
                    .opacity(isTop ? 1 : 0)
                    .allowsHitTesting(isTop)
                    .accessibilityHidden(!isTop)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    // A leaving page stays above the one it reveals.
                    .zIndex(Double(key.index + 1))
            }
            // Only the pages: the root (e.g. the library tabs and their
            // pill) keeps its own animations on a tab change.
            .transaction(value: resetID) { $0.animation = nil }
        }
        // Not `.clipped()`: the lists must reach under the bar for its blur.
        // The window's edge clips a sliding page.
        .scrollContentBackground(.hidden) // lists sit directly on the tinted background
        .environment(\.openPage, OpenPageAction { destination, id in
            openedID = id
            withAnimation(Self.push) { path.append(destination) }
        })
        .environment(\.openedPageID, openedID)
        // The header (and the accessory) as a system bar: lists scroll
        // under it and macOS blurs them there (the scroll edge effect),
        // like under the section titles. The bar reaches up to the window
        // top, so the blur also covers the toolbar area (window buttons,
        // `…` menu); the header itself starts below it.
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header
                accessory()
            }
            .padding(.top, Metrics.contentTop)
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            // Back to the previous page, or to the player from the top level.
            Button(path.isEmpty ? "Back to Player" : "Back", systemImage: "chevron.left") {
                if path.isEmpty {
                    model.page = .player
                } else {
                    withAnimation(Self.push) { _ = path.removeLast() }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(IconButtonStyle(size: 15, frame: 28))
            .keyboardShortcut(.cancelAction) // Esc goes back
            .tooltip(path.isEmpty ? "Back to Player" : "Back")
            Text(title).font(.headline)
            Spacer()
            trailing()
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func page(for destination: BrowseDestination) -> some View {
        switch destination {
        case .playlist(let playlist): PlaylistDetailView(playlist: playlist, model: model)
        case .album(let album): AlbumDetailView(album: album, model: model)
        case .artist(let artist): ArtistDetailView(artist: artist, model: model)
        }
    }
}

extension BrowseStack where Trailing == EmptyView {
    init(
        title: String, path: Binding<[BrowseDestination]>, model: AppModel, resetID: AnyHashable? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder root: @escaping () -> Root
    ) {
        self.init(title: title, path: path, model: model, resetID: resetID, accessory: accessory, trailing: { EmptyView() }, root: root)
    }
}

extension BrowseStack where Accessory == EmptyView, Trailing == EmptyView {
    init(
        title: String, path: Binding<[BrowseDestination]>, model: AppModel, resetID: AnyHashable? = nil,
        @ViewBuilder root: @escaping () -> Root
    ) {
        self.init(title: title, path: path, model: model, resetID: resetID, accessory: { EmptyView() }, trailing: { EmptyView() }, root: root)
    }
}

extension BrowseStack where Accessory == EmptyView {
    init(
        title: String, path: Binding<[BrowseDestination]>, model: AppModel,
        @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder root: @escaping () -> Root
    ) {
        self.init(title: title, path: path, model: model, accessory: { EmptyView() }, trailing: trailing, root: root)
    }
}

/// Opens a playlist / album / artist page in the surrounding `BrowseStack`.
struct OpenPageAction {
    let open: (_ destination: BrowseDestination, _ id: AnyHashable) -> Void

    func callAsFunction<Value: Browsable>(_ value: Value) {
        open(value.destination, AnyHashable(value.id))
    }
}

extension EnvironmentValues {
    @Entry var openPage = OpenPageAction { _, _ in }
    @Entry var openedPageID: AnyHashable?
}

/// A row that opens a page; shown as selected after coming back from it.
struct PageLink<Value: Browsable, Label: View>: View {
    let value: Value
    @ViewBuilder let label: () -> Label
    @Environment(\.openPage) private var openPage
    @Environment(\.openedPageID) private var openedID

    var body: some View {
        Button { openPage(value) } label: {
            label().environment(\.isRowSelected, openedID == AnyHashable(value.id))
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryContent: View {
    enum Tab: String, CaseIterable, Identifiable {
        case playlists = "Playlists", liked = "Liked", albums = "Albums"
        var id: Self { self }
    }

    let model: AppModel
    @State private var tab: Tab = .playlists
    /// Pushed detail pages (playlist / album / artist).
    @State private var path: [BrowseDestination] = []
    @State private var playlists: PagedList<PlaylistSummary>
    @State private var liked: PagedList<TrackSummary>
    @State private var albums: PagedList<AlbumSummary>

    init(library: LibraryService, model: AppModel) {
        self.model = model
        // `State(initialValue:)` sets up @State from init parameters; the lists
        // live as long as this view.
        _playlists = State(initialValue: PagedList(load: { try await library.playlists(offset: $0) }, onError: model.handleLibraryError))
        _liked = State(initialValue: PagedList(load: { try await library.likedSongs(offset: $0) }, onError: model.handleLibraryError))
        _albums = State(initialValue: PagedList(load: { try await library.savedAlbums(offset: $0) }, onError: model.handleLibraryError))
    }

    var body: some View {
        BrowseStack(title: "Library", path: $path, model: model, resetID: tab) {
            // Built like the Search page: a plain list of rows, with the
            // tabs as its bar instead of the search field. One list per tab,
            // all kept alive (each keeps its scroll position), so switching
            // builds nothing while the tabs' pill moves: rebuilding a list
            // on the same frame made the pill stutter. The new tab's list
            // fades in; the old one goes at once (fading both showed the old
            // list blinking under the bar).
            ZStack {
                ForEach(Tab.allCases) { tabList($0) }
            }
            .task(id: tab) { await loadSelectedTab() }
            .safeAreaBar(edge: .top, spacing: 0) { tabs }
            // Reload after a like/unlike in the player (skips the first load).
            .task(id: model.likedSongsVersion) {
                if liked.hasLoaded { await liked.reload() }
            }
        }
        // Reload after an album or playlist was saved / removed (skips the first load).
        .task(id: model.savedCollectionsVersion) {
            if playlists.hasLoaded { await playlists.reload() }
            if albums.hasLoaded { await albums.reload() }
        }
    }

    private func tabList(_ tab: Tab) -> some View {
        let isSelected = tab == self.tab
        return List { tabRows(tab) }
            .libraryList()
            .libraryRowHeight(tab == .liked ? LibraryRowHeight.track : LibraryRowHeight.collection)
            .emptyState(emptyState(tab), when: isEmpty(tab))
            .opacity(isSelected ? 1 : 0)
            .animation(isSelected ? .easeOut(duration: 0.25) : nil, value: isSelected)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }

    /// The system tabs picker, drawn by macOS in Liquid Glass: stretched to
    /// the page width (`.flexible` segments), extra large (taller) and
    /// capsule-shaped.
    private var tabs: some View {
        Picker("Library", selection: tabSelection) {
            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.tabs)
        .labelsHidden()
        .buttonSizing(.flexible)
        .controlSize(.extraLarge)
        .buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// The selected tab's rows (each tab keeps its loaded pages in `PagedList`).
    @ViewBuilder
    private func tabRows(_ tab: Tab) -> some View {
        switch tab {
        case .playlists:
            Section {
                PagedRows(list: playlists) { _, playlist in
                    PageLink(value: playlist) { PlaylistRow(playlist: playlist) }
                }
            } header: {
                ListSectionHeader(count: playlists.total, one: "Playlist", many: "Playlists")
            }
        case .liked where liked.isEmpty:
            EmptyView() // only the empty state
        case .liked:
            // The header (cover, Play, Shuffle) is inside the section, so
            // the title sits above its cover too (see `ListSectionHeader`).
            Section {
                CollectionHeader(
                    imageURL: liked.items.first?.coverURL,
                    title: "Liked Songs",
                    subtitle: "Playlist",
                    details: CollectionHeader.details(of: liked),
                    canPlay: !liked.items.isEmpty,
                    play: { model.play(tracks: liked.items, startingAt: 0, fromLikedSongs: true) },
                    shuffle: { model.play(tracks: liked.items.shuffled(), startingAt: 0, fromLikedSongs: true) }
                )
                .libraryRow()
                PagedRows(list: liked) { index, track in
                    Button { model.play(tracks: liked.items, startingAt: index, fromLikedSongs: true) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            } header: {
                ListSectionHeader(count: liked.total, one: "Song", many: "Songs")
            }
        case .albums:
            Section {
                PagedRows(list: albums) { _, album in
                    PageLink(value: album) { AlbumRow(album: album) }
                }
            } header: {
                ListSectionHeader(count: albums.total, one: "Album", many: "Albums")
            }
        }
    }

    private func isEmpty(_ tab: Tab) -> Bool {
        switch tab {
        case .playlists: playlists.isEmpty
        case .liked: liked.isEmpty
        case .albums: albums.isEmpty
        }
    }

    private func emptyState(_ tab: Tab) -> EmptyState {
        switch tab {
        case .playlists:
            EmptyState(title: "No Playlists", systemImage: "music.note.list",
                       message: "Playlists you create or follow in Spotify appear here.")
        case .liked:
            EmptyState(title: "No Liked Songs", systemImage: "heart",
                       message: "Songs you like, here or in Spotify, appear here.")
        case .albums:
            EmptyState(title: "No Albums", systemImage: "square.stack",
                       message: "Albums you save, here or in Spotify, appear here.")
        }
    }

    /// Loads the first page of the selected tab, once.
    private func loadSelectedTab() async {
        switch tab {
        case .playlists: await playlists.loadIfNeeded()
        case .liked: await liked.loadIfNeeded()
        case .albums: await albums.loadIfNeeded()
        }
    }

    /// Picking a tab also closes any open page, in the same update, so the
    /// new tab's list shows at once.
    private var tabSelection: Binding<Tab> {
        Binding(get: { tab }, set: { newTab in
            tab = newTab
            path = []
        })
    }
}

/// A lazily loaded list: SwiftUI's `List` only creates rows that are visible,
/// and reaching the last row loads the next page.
/// `header` scrolls with the list (e.g. a playlist's cover and buttons). It is
/// inside a section with a song count title, so the title, not the cover,
/// sits under the page's bar (see `ListSectionHeader`).
struct PagedListView<Item: Sendable & Identifiable, Header: View, Row: View>: View {
    let list: PagedList<Item>
    /// Shown under the header when the list is empty.
    let empty: EmptyState
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Int, Item) -> Row

    var body: some View {
        List {
            Section {
                header()
                    .libraryRow()
                PagedRows(list: list, row: row)
                if list.isEmpty {
                    empty.view.libraryRow()
                }
            } header: {
                ListSectionHeader(count: list.total, one: "Song", many: "Songs")
            }
        }
        .libraryList()
        .task { await list.loadIfNeeded() }
    }
}

/// The rows of a `PagedList` inside a `List`: the items (the next page loads
/// as the last rows appear), then a loading or error row. Empty lists are
/// shown by the page (`emptyState`).
struct PagedRows<Item: Sendable & Identifiable, Row: View>: View {
    let list: PagedList<Item>
    @ViewBuilder let row: (Int, Item) -> Row

    var body: some View {
        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
            row(index, item)
                .libraryRow()
                .onAppear { list.rowAppeared(item) }
        }
        // A status row only when there is something to say. (Modifiers on a
        // `Group` around these would leave an empty row, as tall as the
        // list's row height, under short lists.)
        if list.isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                .libraryRow()
        } else if let error = list.error {
            VStack(spacing: 6) {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
                Button("Try Again") { Task { await list.loadMore() } }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .libraryRow()
        }
    }
}

