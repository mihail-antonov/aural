import AuralCore
import SwiftUI

/// A cover image for lists and pages, loaded through `ArtworkLoader`: from
/// the capped disk cache when possible, and decoded at the size it is shown
/// at. Used instead of `AsyncImage`, which decodes the full image and keeps
/// downloads in the shared URL cache.
///
/// The decoded image lives in this view's `@State`, so it is released when
/// the view goes away (e.g. a `List` row scrolled off screen).
struct ArtworkImage<Placeholder: View>: View {
    let url: URL?
    /// Size on screen in points; the image is decoded for the display's scale.
    let size: CGFloat
    @ViewBuilder var placeholder: Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        // `task(id:)` restarts when the URL changes and is cancelled when the
        // view disappears, so scrolled-away rows stop loading.
        .task(id: url) {
            image = nil
            guard let url else { return }
            let pixels = Int((size * displayScale).rounded(.up))
            image = try? await ArtworkLoader.load(url, maxPixelSize: pixels)
        }
    }
}
