import Foundation
import WebKit

/// URL scheme security policy for bridge panes.
///
/// Strict allowlist: only `agentstudio` (custom scheme for bundled React app)
/// and `about` (initial blank page). All web schemes (https, http, file, etc.)
/// are blocked — bridge panes must NOT navigate to external content.
final class BridgeNavigationDecider: WebPage.NavigationDeciding {

    // MARK: - Allowed Schemes

    static let allowedSchemes: Set<String> = [
        "agentstudio", "about"
    ]

    // MARK: - NavigationDeciding

    @MainActor
    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""

        // Block all schemes except agentstudio and about
        guard Self.allowedSchemes.contains(scheme) else {
            return .cancel
        }

        return .allow
    }
}
