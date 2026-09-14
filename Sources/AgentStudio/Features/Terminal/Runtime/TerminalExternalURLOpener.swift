import AppKit
import Foundation

/// Opens intentional terminal link clicks with the system's registered handler.
/// Called by the runtime after the Ghostty callback's MainActor hop, so opening
/// does not reenter AppKit while Ghostty handles the mouse event.
@MainActor
enum TerminalExternalURLOpener {
    static func open(_ target: String) {
        open(target, using: { NSWorkspace.shared.open($0) })
    }

    static func open(_ target: String, using opener: (URL) -> Bool) {
        guard let url = resolve(target) else { return }
        _ = opener(url)
    }

    nonisolated static func resolve(_ target: String) -> URL? {
        guard !target.isEmpty else { return nil }
        if let url = URL(string: target), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: NSString(string: target).standardizingPath)
    }
}
