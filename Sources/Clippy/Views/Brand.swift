import SwiftUI

/// Accent colour source. Normally the user's system accent (native behaviour). When exporting website
/// screenshots (`Clippy --export-screenshots`) it is Clippy's brand purple, and platform-backed views
/// (text fields, scroll views, vibrancy) are swapped for plain SwiftUI so ImageRenderer can draw them.
enum Brand {
    @MainActor static var exporting = false
    @MainActor static var accent: Color { exporting ? Color(red: 0.545, green: 0.361, blue: 0.965) : .accentColor }
}
