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
/// from the top level.
struct BrowseStack<Root: View>: View {
    let title: String
    @Binding var path: NavigationPath
    let model: AppModel
    @ViewBuilder let root: () -> Root

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

            NavigationStack(path: $path) {
                root()
                    .withoutToolbarItems()
                    .navigationDestination(for: PlaylistSummary.self) { PlaylistDetailView(playlist: $0, model: model).withoutToolbarItems() }
                    .navigationDestination(for: AlbumSummary.self) { AlbumDetailView(album: $0, model: model).withoutToolbarItems() }
                    .navigationDestination(for: ArtistSummary.self) { ArtistDetailView(artist: $0, model: model).withoutToolbarItems() }
            }
            .scrollContentBackground(.hidden) // lists sit directly on the tinted background
        }
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
            VStack(spacing: 0) {
                GlassSegmentedControl(selection: $tab, items: Tab.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                switch tab {
                case .playlists:
                    PagedListView(list: playlists) { _, playlist in
                        NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }
                    }
                case .liked:
                    PagedListView(list: liked) { index, track in
                        Button { model.play(tracks: liked.items, startingAt: index) } label: { TrackRow(track: track) }
                            .buttonStyle(.plain)
                    }
                    // Reload after a like/unlike in the player (skips the first load).
                    .task(id: model.likedSongsVersion) {
                        if liked.hasLoaded { await liked.reload() }
                    }
                case .albums:
                    PagedListView(list: albums) { _, album in
                        NavigationLink(value: album) { AlbumRow(album: album) }
                    }
                }
            }
        }
    }
}

/// A lazily loaded list: SwiftUI's `List` only creates rows that are visible,
/// and reaching the last row loads the next page.
struct PagedListView<Item: Sendable & Identifiable, Row: View>: View {
    let list: PagedList<Item>
    @ViewBuilder let row: (Int, Item) -> Row

    var body: some View {
        List {
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
