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

/// Items that open a page when clicked.
protocol Browsable: Identifiable where ID: Hashable {
    var destination: BrowseDestination { get }
}

extension PlaylistSummary: Browsable { var destination: BrowseDestination { .playlist(self) } }
extension AlbumSummary: Browsable { var destination: BrowseDestination { .album(self) } }
extension ArtistSummary: Browsable { var destination: BrowseDestination { .artist(self) } }

/// A page header and a stack of playlist / album / artist pages, built on the
/// system `NavigationStack`. Going back is the header's chevron (or Esc),
/// which returns to the player from the top level. `accessory` (the library
/// tabs) stays visible above every page.
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

    var body: some View {
        // The system stack keeps the list (scroll position, loaded pages)
        // alive under a pushed page and animates push and pop. Aural's
        // header replaces its back button and title.
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: BrowseDestination.self) { destination in
                    page(for: destination)
                        .navigationBarBackButtonHidden(true)
                }
        }
        .scrollContentBackground(.hidden) // lists sit directly on the tinted background
        .transaction(value: resetID) { $0.animation = nil }
        .environment(\.openPage, OpenPageAction { destination, id in
            openedID = id
            path.append(destination)
        })
        .environment(\.openedPageID, openedID)
        // The header (and the library tabs) as a system bar: lists scroll
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
                    _ = path.removeLast()
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
            // The lists cross-fade when the tab changes. `BrowseStack` turns
            // animations off for a tab change (so open pages vanish at once);
            // this animation, set further down, applies to the lists only.
            // Built like the Search page: a plain list of rows, with the
            // tabs as its bar instead of the search field.
            ZStack {
                List { tabRows }
                    .libraryList()
                    // A new list per tab: it starts at the top and fades in.
                    .id(tab)
                    .task(id: tab) { await loadSelectedTab() }
            }
            .animation(.easeInOut(duration: 0.2), value: tab)
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
    private var tabRows: some View {
        switch tab {
        case .playlists:
            Section {
                PagedRows(list: playlists, inSection: true) { _, playlist in
                    PageLink(value: playlist) { PlaylistRow(playlist: playlist) }
                }
            } header: {
                ListSectionHeader(title: Self.countTitle(playlists.total, one: "Playlist", many: "Playlists"))
            }
        case .liked:
            // The header (cover, Play, Shuffle) is inside the section, so
            // the title sits above its cover too (see `countTitle`).
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
                .librarySectionRow(isFirst: true, isLast: false)
                PagedRows(list: liked) { index, track in
                    Button { model.play(tracks: liked.items, startingAt: index, fromLikedSongs: true) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            } header: {
                ListSectionHeader(title: Self.countTitle(liked.total, one: "Song", many: "Songs"))
            }
        case .albums:
            Section {
                PagedRows(list: albums, inSection: true) { _, album in
                    PageLink(value: album) { AlbumRow(album: album) }
                }
            } header: {
                ListSectionHeader(title: Self.countTitle(albums.total, one: "Album", many: "Albums"))
            }
        }
    }

    /// Section title with the number of items on Spotify, e.g. "48 Playlists"
    /// (just "Playlists" until the first page has loaded).
    ///
    /// The section title also keeps the bar's blur neutral: pinned right
    /// under the tabs, it is what the bar's scroll edge effect sees, as on
    /// the Search and Queue pages. Without it the first cover sat directly
    /// under the bar and its color bled into the blur.
    private static func countTitle(_ total: Int?, one: String, many: String) -> String {
        guard let total else { return many }
        return "\(total) \(total == 1 ? one : many)"
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
/// `header` scrolls with the list (e.g. a playlist's cover and buttons).
struct PagedListView<Item: Sendable & Identifiable, Header: View, Row: View>: View {
    let list: PagedList<Item>
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Int, Item) -> Row

    var body: some View {
        List {
            header()
                .libraryRow()
            PagedRows(list: list, row: row)
        }
        .libraryList()
        .task { await list.loadIfNeeded() }
    }
}

/// The rows of a `PagedList` inside a `List`: the items (the next page loads
/// as the last rows appear), then a loading, error or empty row.
struct PagedRows<Item: Sendable & Identifiable, Row: View>: View {
    let list: PagedList<Item>
    /// Inside a `Section`: the first row gets extra room under the title.
    var inSection = false
    @ViewBuilder let row: (Int, Item) -> Row

    var body: some View {
        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
            row(index, item)
                .librarySectionRow(isFirst: inSection && index == 0, isLast: false)
                .onAppear { list.rowAppeared(item) }
        }
        Group {
            if list.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if let error = list.error {
                VStack(spacing: 6) {
                    Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
                    Button("Try Again") { Task { await list.loadMore() } }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
            } else if list.hasLoaded && list.items.isEmpty {
                Text("Nothing here yet.").foregroundStyle(.secondary)
            }
        }
        .libraryRow()
        .listRowSeparator(.hidden)
    }
}

extension PagedListView where Header == EmptyView {
    init(list: PagedList<Item>, @ViewBuilder row: @escaping (Int, Item) -> Row) {
        self.init(list: list, header: { EmptyView() }, row: row)
    }
}
