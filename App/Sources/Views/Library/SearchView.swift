import AuralCore
import SwiftUI

/// Search for tracks, albums, artists and playlists (first 10 of each —
/// Spotify's limit per request in Development Mode).
struct SearchView: View {
    let model: AppModel
    @State private var text = ""
    @State private var results = SearchResults.empty
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Rounded search field on glass, like the iOS search bar.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                TextField("Search Spotify", text: $text)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                if !results.tracks.isEmpty {
                    Section {
                        ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
                            Button { model.play(tracks: results.tracks, startingAt: index) } label: { TrackRow(track: track) }
                                .buttonStyle(.plain)
                                .libraryRow()
                        }
                    } header: { SearchSectionHeader(title: "Songs") }
                }
                if !results.artists.isEmpty {
                    Section {
                        ForEach(results.artists) { artist in
                            NavigationLink(value: artist) { ArtistRow(artist: artist) }
                                .libraryRow()
                        }
                    } header: { SearchSectionHeader(title: "Artists") }
                }
                if !results.albums.isEmpty {
                    Section {
                        ForEach(results.albums) { album in
                            NavigationLink(value: album) { AlbumRow(album: album) }
                                .libraryRow()
                        }
                    } header: { SearchSectionHeader(title: "Albums") }
                }
                if !results.playlists.isEmpty {
                    Section {
                        ForEach(results.playlists) { playlist in
                            NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }
                                .libraryRow()
                        }
                    } header: { SearchSectionHeader(title: "Playlists") }
                }
                if isSearching { ProgressView().controlSize(.small).frame(maxWidth: .infinity).libraryRow() }
                if let error { Text(error).font(.caption).foregroundStyle(.red).libraryRow() }
            }
            .libraryList()
        }
        // `task(id:)` restarts whenever the text changes and cancels the
        // previous run, which gives us a debounce for free.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let library = model.library else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let found = try await library.search(text)
                guard !Task.isCancelled else { return }
                results = found
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                model.handleLibraryError(error)
            }
        }
    }
}

/// iOS-style section title: large, bold, left-aligned, not uppercased.
private struct SearchSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .textCase(nil)
            .padding(.top, 8)
    }
}
