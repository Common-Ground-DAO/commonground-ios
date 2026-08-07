import SwiftUI

/// Product-level values that publishers are expected to replace before a
/// branded release. Keeping them here avoids scattering provisional values
/// through views and session orchestration.
enum AppConfiguration {
    static let productName = "Common Ground"
    static let defaultInstanceURL = "https://cg.mogged.eu"
    static let supportEmail = "support@example.com"
    static let privacyURL = URL(string: "https://example.com/privacy")!
}

enum AppTheme {
    static let accent = Color.orange
    static let secondaryAccent = Color.yellow

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
