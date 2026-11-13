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
      GlassField(placeholder: "Search Spotify", text: $text, systemImage: "magnifyingglass")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

      List {
        if !results.tracks.isEmpty {
          SearchSectionHeader(title: "Songs")
          ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
            Button {
              model.play(tracks: results.tracks, startingAt: index)
            } label: {
              TrackRow(track: track)
            }
            .buttonStyle(.plain)
            .libraryRow()
          }
        }
        if !results.artists.isEmpty {
          SearchSectionHeader(title: "Artists")
          ForEach(results.artists) { artist in
            PageLink(value: artist) { ArtistRow(artist: artist) }
              .libraryRow()
          }
        }
        if !results.albums.isEmpty {
          SearchSectionHeader(title: "Albums")
          ForEach(results.albums) { album in
            PageLink(value: album) { AlbumRow(album: album) }
              .libraryRow()
          }
        }
        if !results.playlists.isEmpty {
          SearchSectionHeader(title: "Playlists")
          ForEach(results.playlists) { playlist in
            PageLink(value: playlist) { PlaylistRow(playlist: playlist) }
              .libraryRow()
          }
        }
        if isSearching {
          ProgressView().controlSize(.small).frame(maxWidth: .infinity).libraryRow()
        }
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
/// A plain list row rather than a `Section` header, so it has the same side
/// insets as the rows, no separator line under it, and room around it.
private struct SearchSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 17, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 12)
      .padding(.bottom, 6)
      .libraryRow()
      .accessibilityAddTraits(.isHeader)
  }
}
