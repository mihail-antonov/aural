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

/// The Search page, opened with the player's search button.
struct SearchPage: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

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

/// A page header and a navigation stack for playlist / album / artist pages.
/// Going back is the header's chevron (or Esc), which returns to the player
/// from the top level. `accessory` (the library tabs) stays visible above
/// every page of the stack.
struct BrowseStack<Accessory: View, Root: View>: View {
    let title: String
    @Binding var path: NavigationPath
    let model: AppModel
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let root: () -> Root
    /// The row opened last: marked as selected when coming back to the list.
    @State private var openedID: AnyHashable?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                // Back to the previous page, or to the player from the top level.
                Button(path.isEmpty ? "Back to Player" : "Back", systemImage: "chevron.left") {
                    if path.isEmpty { model.page = .player } else { path.removeLast() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(IconButtonStyle(size: 15, frame: 28))
                .keyboardShortcut(.cancelAction) // Esc goes back
                Text(title).font(.headline)
                Spacer()
            }
            .frame(height: 28)
            .padding(.horizontal, 14)

            accessory()

            NavigationStack(path: $path) {
                root()
                    .withoutToolbarItems()
                    .navigationDestination(for: PlaylistSummary.self) { PlaylistDetailView(playlist: $0, model: model).withoutToolbarItems() }
                    .navigationDestination(for: AlbumSummary.self) { AlbumDetailView(album: $0, model: model).withoutToolbarItems() }
                    .navigationDestination(for: ArtistSummary.self) { ArtistDetailView(artist: $0, model: model).withoutToolbarItems() }
            }
            .scrollContentBackground(.hidden) // lists sit directly on the tinted background
            .environment(\.openPage, OpenPageAction { value, id in
                openedID = id
                // The path needs the concrete type: `navigationDestination(for:)`
                // matches on it (an `AnyHashable` would match no destination).
                switch value.base {
                case let playlist as PlaylistSummary: path.append(playlist)
                case let album as AlbumSummary: path.append(album)
                case let artist as ArtistSummary: path.append(artist)
                default: assertionFailure("No page for \(type(of: value.base))")
                }
            })
            .environment(\.openedPageID, openedID)
        }
    }
}

extension BrowseStack where Accessory == EmptyView {
    init(title: String, path: Binding<NavigationPath>, model: AppModel, @ViewBuilder root: @escaping () -> Root) {
        self.init(title: title, path: path, model: model, accessory: { EmptyView() }, root: root)
    }
}

/// Opens a playlist / album / artist page in the surrounding `BrowseStack`.
/// (A `NavigationLink` in a macOS `List` leaves a blue system selection on the
/// row after going back; Aural draws its own selected state instead.)
struct OpenPageAction {
    let open: (_ value: AnyHashable, _ id: AnyHashable) -> Void

    func callAsFunction<Value: Hashable & Identifiable>(_ value: Value) {
        open(AnyHashable(value), AnyHashable(value.id))
    }
}

extension EnvironmentValues {
    @Entry var openPage = OpenPageAction { _, _ in }
    @Entry var openedPageID: AnyHashable?
}

/// A row that opens a page; shown as selected after coming back from it.
struct PageLink<Value: Hashable & Identifiable, Label: View>: View {
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

private extension View {
    /// `NavigationStack` normally puts a back button and the page title into
    /// the window's toolbar. Aural's header does that job instead. (Hiding the
    /// whole window toolbar is not an option: it also hides the window buttons.)
    func withoutToolbarItems() -> some View {
        navigationBarBackButtonHidden(true)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
    @State private var path = NavigationPath()
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
        BrowseStack(title: "Library", path: $path, model: model) {
            // The tabs stay visible on playlist and album pages too; picking
            // a tab there goes back to that tab's list.
            GlassSegmentedControl(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue) })
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        } root: {
            switch tab {
            case .playlists:
                PagedListView(list: playlists) { _, playlist in
                    PageLink(value: playlist) { PlaylistRow(playlist: playlist) }
                }
            case .liked:
                PagedListView(list: liked) {
                    CollectionHeader(
                        imageURL: liked.items.first?.coverURL,
                        title: "Liked Songs",
                        subtitle: "Playlist",
                        canPlay: !liked.items.isEmpty,
                        play: { model.play(tracks: liked.items, startingAt: 0) },
                        shuffle: { model.play(tracks: liked.items.shuffled(), startingAt: 0) }
                    )
                } row: { index, track in
                    Button { model.play(tracks: liked.items, startingAt: index) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
                // Reload after a like/unlike in the player (skips the first load).
                .task(id: model.likedSongsVersion) {
                    if liked.hasLoaded { await liked.reload() }
                }
            case .albums:
                PagedListView(list: albums) { _, album in
                    PageLink(value: album) { AlbumRow(album: album) }
                }
            }
        }
        .onChange(of: tab) { path = NavigationPath() }
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
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                row(index, item)
                    .libraryRow()
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
        .libraryList()
        .task { await list.loadIfNeeded() }
    }
}

extension PagedListView where Header == EmptyView {
    init(list: PagedList<Item>, @ViewBuilder row: @escaping (Int, Item) -> Row) {
        self.init(list: list, header: { EmptyView() }, row: row)
    }
}
