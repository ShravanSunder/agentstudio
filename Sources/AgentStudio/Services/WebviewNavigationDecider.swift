import Foundation
import WebKit

/// URL scheme security policy for webview panes.
///
/// Allowed schemes: https, http, about, file, agentstudio (OAuth callback).
/// Blocked schemes: javascript, data, blob, and unknown schemes.
///
/// `target=_blank` links are loaded in the current page (single-page-per-pane model).
final class WebviewNavigationDecider: WebPage.NavigationDeciding {

    // MARK: - Allowed Schemes

    static let allowedSchemes: Set<String> = [
        "https", "http", "about", "file", "agentstudio"
    ]

    // MARK: - NavigationDeciding

    @MainActor
    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""

        // Block dangerous schemes
        guard Self.allowedSchemes.contains(scheme) else {
            return .cancel
        }

        return .allow
    }
}
