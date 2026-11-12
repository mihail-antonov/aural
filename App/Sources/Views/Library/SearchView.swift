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
            TextField("Search Spotify", text: $text)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            List {
                if !results.tracks.isEmpty {
                    Section("Tracks") {
                        ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
                            Button { model.play(tracks: results.tracks, startingAt: index) } label: { TrackRow(track: track) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !results.artists.isEmpty {
                    Section("Artists") {
                        ForEach(results.artists) { artist in
                            NavigationLink(value: artist) { ArtistRow(artist: artist) }
                        }
                    }
                }
                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums) { album in
                            NavigationLink(value: album) { AlbumRow(album: album) }
                        }
                    }
                }
                if !results.playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(results.playlists) { playlist in
                            NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }
                        }
                    }
                }
                if isSearching { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
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
