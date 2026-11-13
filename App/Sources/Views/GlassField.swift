import SwiftUI

/// A text field on a Liquid Glass capsule, like the iOS search bar. Used for
/// search and for the setup steps' key and Client ID.
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String?
    /// Hides the typed text (API keys).
    var isSecure = false
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.white.opacity(0.6))
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassEffect(.regular, in: .capsule)
    }
}
