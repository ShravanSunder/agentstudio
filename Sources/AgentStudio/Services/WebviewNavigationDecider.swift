import Foundation
import WebKit

/// URL scheme security policy for webview panes.
///
/// Allowed schemes: https, http, about, file, agentstudio (OAuth callback).
/// Blocked schemes: javascript, data, blob, and unknown schemes.
///
/// Also handles `target=_blank` links by delegating to a callback
/// that opens the URL in a new tab instead of a new window.
///
/// Uses a class (not struct) to ensure the `onNewTabRequested` closure
/// survives being passed into `WebPage` init without value-copy issues.
final class WebviewNavigationDecider: WebPage.NavigationDeciding {

    /// Called when a navigation with `target=_blank` is intercepted.
    /// The handler should open the URL in a new tab.
    var onNewTabRequested: ((URL) -> Void)?

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

        // Handle target=_blank: open in new tab, cancel the navigation
        if action.target == nil, action.navigationType == .linkActivated {
            onNewTabRequested?(url)
            return .cancel
        }

        return .allow
    }
}
