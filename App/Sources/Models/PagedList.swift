import AuralCore
import Foundation
import Observation

/// A list loaded page by page as the user scrolls (Spotify returns at most
/// 50 items per request). Only small summaries are kept, never JSON.
@MainActor
@Observable
final class PagedList<Item: Sendable & Identifiable> {
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var error: (any Error)?
    private(set) var hasLoaded = false
    /// Number of items on Spotify (all pages), once the first page has loaded.
    private(set) var total: Int?
    /// True once every page has loaded.
    private(set) var isComplete = false

    @ObservationIgnored private var nextOffset: Int? = 0
    @ObservationIgnored private let load: (Int) async throws -> Page<Item>
    @ObservationIgnored private let onError: (any Error) -> Void

    /// - Parameter load: fetches the page starting at the given offset.
    init(load: @escaping (Int) async throws -> Page<Item>, onError: @escaping (any Error) -> Void = { _ in }) {
        self.load = load
        self.onError = onError
    }

    var canLoadMore: Bool { nextOffset != nil && !isLoading }

    /// Loads the first page once, or again if that failed.
    func loadIfNeeded() async {
        guard !hasLoaded || (error != nil && items.isEmpty) else { return }
        await loadMore()
    }

    func loadMore() async {
        guard let offset = nextOffset, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(offset)
            items.append(contentsOf: page.items)
            nextOffset = page.nextOffset
            total = page.total
            isComplete = page.nextOffset == nil
            error = nil
        } catch {
            // Switching tabs cancels the view's task and with it the request.
            // That is not an error: the list simply loads when shown again.
            if Task.isCancelled { return }
            self.error = error
            onError(error)
        }
        hasLoaded = true
    }

    /// Drops everything and loads the first page again.
    func reload() async {
        guard !isLoading else { return }
        items = []
        nextOffset = 0
        hasLoaded = false
        isComplete = false
        await loadMore()
    }

    /// Call from a row's `onAppear`: loads the next page when the last row shows.
    func rowAppeared(_ item: Item) {
        guard item.id == items.last?.id, canLoadMore else { return }
        Task { await loadMore() }
    }
}
