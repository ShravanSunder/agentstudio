import AppKit
import Foundation
import WebKit
import os.log

private let navigationLogger = Logger(subsystem: "com.agentstudio", category: "BridgeNavigationDecider")

/// URL scheme security policy for bridge panes.
///
/// Strict allowlist: only `agentstudio` (custom scheme for bundled React app)
/// and `about` (initial blank page) are loaded in the pane. External URLs
/// (`http`/`https`) are opened in the default browser instead.
/// All other schemes (file, ftp, etc.) are blocked silently.
///
final class BridgeNavigationDecider: WebPage.NavigationDeciding {

    // MARK: - Allowed Schemes

    static let allowedSchemes: Set<String> = [
        "agentstudio", "about",
    ]

    /// Schemes that should be redirected to the default browser, not loaded in-pane.
    static let externalSchemes: Set<String> = [
        "http", "https",
    ]

    // MARK: - NavigationDeciding

    @MainActor
    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""

        // Internal schemes: load in pane
        if Self.allowedSchemes.contains(scheme) {
            return .allow
        }

        // External web URLs: open in default browser, don't load in pane
        if Self.externalSchemes.contains(scheme) {
            navigationLogger.debug("[BridgeNavigationDecider] opening external URL in browser: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            return .cancel
        }

        // Everything else: block silently
        return .cancel
    }
}
