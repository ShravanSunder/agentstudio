import AgentStudioInfrastructure
import Foundation

/// Pure text contraction for deriving a notification-safe "last output line"
/// from a raw multi-row Ghostty viewport read. This is the Contract 7 source
/// boundary: bounded, exhaustive contraction happens here, independent of the
/// Ghostty C API call that produced the raw text and the settle-timing actor
/// that invokes it. Nothing in this type touches MainActor or Ghostty state.
enum TerminalLastOutputLineContract {
    /// Returns the trailing non-empty, contracted line found in `rawText`
    /// with no bare-prompt or signature filtering — used only to learn a
    /// pane's prompt signature at a commandFinished-driven settle, where
    /// that trailing line is by construction the shell's freshly-printed
    /// prompt (shell integration prints the new prompt immediately after the
    /// command ends). Not a candidate for the rendered last-output-line
    /// itself; see `contractedLastLine`.
    static func trailingNonEmptyLine(fromRawViewportText rawText: String) -> String? {
        for rawLine in rawText.components(separatedBy: "\n").reversed() {
            if let normalized = normalizedLine(rawLine) { return normalized }
        }
        return nil
    }

    /// Returns the last non-empty, contracted line found in `rawText`, or nil
    /// when no printable content remains after contraction (empty read, only
    /// blank rows, the only remaining row is a bare shell prompt, or every
    /// remaining row matches `promptSignature`).
    ///
    /// `promptSignature` is the pane's learned prompt line (see
    /// `trailingNonEmptyLine`), normalized the same way as this function's
    /// own candidates, so an exact match reliably excludes a freshly-printed
    /// prompt even when it embeds real text (directory names, branch names)
    /// that the zero-letters `isBarePromptLine` heuristic alone cannot
    /// recognize as a prompt. The zero-letters heuristic remains as a
    /// fallback for panes with no learned signature yet (e.g. the very first
    /// settle, before the caller has recorded one).
    static func contractedLastLine(
        fromRawViewportText rawText: String,
        excluding promptSignature: String? = nil
    ) -> String? {
        for rawLine in rawText.components(separatedBy: "\n").reversed() {
            guard let normalized = normalizedLine(rawLine) else { continue }
            guard !isBarePromptLine(normalized), normalized != promptSignature else { continue }
            return normalized
        }
        return nil
    }

    /// Trims, strips control residue, and byte-bounds a raw viewport row;
    /// returns nil when nothing printable remains. Shared normalization so a
    /// learned prompt signature and a later candidate line compare equal
    /// under the exact same transform.
    private static func normalizedLine(_ rawLine: String) -> String? {
        let trimmed = strippingControlResidue(rawLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return bounded(trimmed, toUTF8ByteCount: AppPolicies.TerminalOutputCapture.maxLastOutputLineUTF8Bytes)
    }

    /// Replaces control characters (escape residue, NUL, BEL, etc.) with a
    /// space so words on either side don't merge; a later trim collapses any
    /// resulting edge whitespace.
    private static func strippingControlResidue(_ line: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in line.unicodeScalars {
            result.append(CharacterSet.controlCharacters.contains(scalar) ? " " : scalar)
        }
        return String(result)
    }

    /// A line with no letters or digits carries no output content — it is
    /// the bare prompt glyph (e.g. "$", "%", "➜ ~") rather than real output.
    private static func isBarePromptLine(_ trimmedLine: String) -> Bool {
        !trimmedLine.contains { $0.isLetter || $0.isNumber }
    }

    private static func bounded(_ line: String, toUTF8ByteCount maxBytes: Int) -> String {
        guard line.utf8.count > maxBytes else { return line }
        var byteCount = 0
        var scalars = String.UnicodeScalarView()
        for scalar in line.unicodeScalars {
            let scalarByteCount = String(scalar).utf8.count
            guard byteCount + scalarByteCount <= maxBytes else { break }
            scalars.append(scalar)
            byteCount += scalarByteCount
        }
        return String(scalars)
    }
}
