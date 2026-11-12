import AuralCore
import SwiftUI

/// Plain Stage 3 library window: playlists, Liked Songs, saved albums, search.
/// The designed panel replaces it in Stage 4.
struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let library = model.library {
                LibraryContent(library: library, model: model)
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
        .frame(minWidth: 360, minHeight: 480)
    }
}

private struct LibraryContent: View {
    enum Tab: String, CaseIterable, Identifiable {
        case playlists = "Playlists", liked = "Liked", albums = "Albums", search = "Search"
        var id: Self { self }
    }

    let model: AppModel
    @State private var tab: Tab = .playlists
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
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)

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
                case .search:
                    SearchView(model: model)
                }
            }
            .navigationDestination(for: PlaylistSummary.self) { PlaylistDetailView(playlist: $0, model: model) }
            .navigationDestination(for: AlbumSummary.self) { AlbumDetailView(album: $0, model: model) }
            .navigationDestination(for: ArtistSummary.self) { ArtistDetailView(artist: $0, model: model) }
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
                    .onAppear { list.rowAppeared(item) }
            }
            if list.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = list.error {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            } else if list.hasLoaded && list.items.isEmpty {
                Text("Nothing here yet.").foregroundStyle(.secondary)
            }
        }
        .task { await list.loadIfNeeded() }
    }
}
