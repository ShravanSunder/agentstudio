import AgentStudioInfrastructure
import Foundation
import GhosttyKit

extension SurfaceManager {
    /// Reads the raw viewport text for `surfaceID`. One MainActor Ghostty
    /// call per settled burst (never per output event, never on a timer) —
    /// the caller (`TerminalActivityProjector`) invokes this only at settle
    /// time and owns all line-level contraction
    /// (`TerminalLastOutputLineContract`), since only it holds the per-pane
    /// learned prompt signature and unchanged-line suppression state that
    /// contraction needs.
    ///
    /// The selection spans the full `GHOSTTY_POINT_VIEWPORT` region using
    /// `GHOSTTY_POINT_COORD_TOP_LEFT` / `GHOSTTY_POINT_COORD_BOTTOM_RIGHT`
    /// for both endpoints — mirroring Ghostty's own macOS host read
    /// (`SurfaceView_AppKit.swift`'s `cachedVisibleContents`) — rather than
    /// computing a trailing-row-count offset ourselves. Ghostty's viewport
    /// bottom-right is defined as the last *written* row, not the last row
    /// of the grid; a grid-relative offset (e.g. "N rows above the visible
    /// bottom") sits below that written boundary whenever real output
    /// doesn't fill the whole viewport height, which inverts the selection
    /// order and yields a degenerate, effectively empty read. A full-viewport
    /// read has no such row math and costs the same one Ghostty call; the
    /// caller already walks the text backwards to find trailing lines.
    ///
    /// Returns nil when the surface is unavailable, the viewport has no
    /// rows, or the read fails.
    package func readViewportTrailingText(forSurfaceID surfaceID: UUID) -> String? {
        let result = withSurface(surfaceID) { surface -> String? in
            let size = ghostty_surface_size(surface)
            guard size.rows > 0 else { return nil }
            let selection = ghostty_selection_s(
                top_left: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                    x: 0,
                    y: 0
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
        guard case .success(let rawText) = result else { return nil }
        return rawText
    }
}
