import AgentStudioInfrastructure
import Foundation
import GhosttyKit

extension SurfaceManager {
    /// Reads a notification-safe "last output line" candidate from the
    /// surface's trailing viewport rows. One MainActor Ghostty call per
    /// settled burst (never per output event, never on a timer) — the caller
    /// (`TerminalActivityProjector`) invokes this only at settle time.
    ///
    /// Returns nil when the surface is unavailable, the viewport has no
    /// rows, the read fails, or the only printable content is a bare shell
    /// prompt line (see `TerminalLastOutputLineContract`).
    package func readLastOutputLine(forSurfaceID surfaceID: UUID) -> String? {
        let result = withSurface(surfaceID) { surface -> String? in
            let size = ghostty_surface_size(surface)
            guard size.rows > 0 else { return nil }
            let viewportRowCount = Int(size.rows)
            let firstRow = UInt32(max(0, viewportRowCount - AppPolicies.TerminalOutputCapture.viewportRowWindow))
            let selection = ghostty_selection_s(
                top_left: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_EXACT,
                    x: 0,
                    y: firstRow
                ),
                bottom_right: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                    x: 0,
                    y: 0
                ),
                rectangle: false
            )
            var text = ghostty_text_s()
            guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
            defer { ghostty_surface_free_text(surface, &text) }
            guard let cText = text.text, text.text_len > 0 else { return nil }
            let bytes = UnsafeRawBufferPointer(start: UnsafeRawPointer(cText), count: Int(text.text_len))
            return String(bytes: bytes, encoding: .utf8)
        }
        guard case .success(let rawText) = result, let rawText else { return nil }
        return TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawText)
    }
}
