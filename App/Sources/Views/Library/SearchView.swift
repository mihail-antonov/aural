import AuralCore
import SwiftUI

/// Search for tracks, albums, artists and playlists (first 10 of each —
/// Spotify's limit per request in Development Mode).
struct SearchView: View {
  let model: AppModel
  @State private var text = ""
  @State private var results = SearchResults.empty
  /// The text `results` belong to.
  @State private var searchedText = ""
  @State private var isSearching = false
  @State private var error: String?

  var body: some View {
    List {
      section("Songs", results.tracks) { index, track in
        Button {
          model.play(tracks: results.tracks, startingAt: index)
        } label: {
          TrackRow(track: track)
        }
        .buttonStyle(.plain)
      }
      section("Artists", results.artists) { _, artist in
        PageLink(value: artist) { ArtistRow(artist: artist) }
      }
      section("Albums", results.albums) { _, album in
        PageLink(value: album) { AlbumRow(album: album) }
      }
      section("Playlists", results.playlists) { _, playlist in
        PageLink(value: playlist) { PlaylistRow(playlist: playlist) }
      }
      if isSearching {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity).libraryRow()
      }
      if let error { Text(error).font(.caption).foregroundStyle(.red).libraryRow() }
    }
    .libraryList()
    // The system "No Results for …" view, centered.
    .overlay {
      if !isSearching, error == nil, results.isEmpty,
         !searchedText.trimmingCharacters(in: .whitespaces).isEmpty, searchedText == text {
        ContentUnavailableView.search(text: searchedText)
      }
    }
    // The field as a system bar: results scroll under it, blurred by
    // macOS (the scroll edge effect), like under the page header.
    .safeAreaBar(edge: .top, spacing: 0) {
      GlassField(placeholder: "Search Spotify", text: $text, systemImage: "magnifyingglass")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        searchedText = text
        error = nil
      } catch {
        guard !Task.isCancelled else { return }
        self.error = error.localizedDescription
        model.handleLibraryError(error)
      }
    }
  }

  /// One kind of result as a native list section; nothing when it is empty.
  @ViewBuilder
  private func section<Item: Identifiable, Row: View>(
    _ title: String, _ items: [Item], @ViewBuilder row: @escaping (Int, Item) -> Row
  ) -> some View {
    if !items.isEmpty {
      Section {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          row(index, item).libraryRow()
        }
      } header: {
        ListSectionHeader(title: title)
      } footer: {
        // Extra room before the next kind of result. (A pinned title's own
        // padding alone was not enough room between the groups.)
        Color.clear.frame(height: LibrarySpacing.betweenSearchGroups)
      }
    }
  }
}
