import Foundation
import WebKit

/// Handles JavaScript dialogs (alert, confirm, prompt) and file input prompts
/// for webview panes. Uses the default WebKit implementations for now.
///
/// This type exists as an explicit conformance point so we can customize
/// dialog behavior later (e.g., styled alert panels, file picker integration).
final class WebviewDialogHandler: WebPage.DialogPresenting {
    // All methods use default implementations from the protocol extension.
    // Override specific methods here when custom behavior is needed.
}
