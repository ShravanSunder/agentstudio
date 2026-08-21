import AgentStudioInfrastructure
import Foundation

/// Pure text contraction for deriving a notification-safe "last output line"
/// from a raw multi-row Ghostty viewport read. This is the Contract 7 source
/// boundary: bounded, exhaustive contraction happens here, independent of the
/// Ghostty C API call that produced the raw text and the settle-timing actor
/// that invokes it. Nothing in this type touches MainActor or Ghostty state.
enum TerminalLastOutputLineContract {
    /// Returns the last non-empty, contracted viewport line without trying to classify shell
    /// prompts, echoed commands, command output, or TUI content. Ghostty exposes terminal cells,
    /// not those semantic categories, so preserving the literal trailing line is more honest than
    /// applying prompt heuristics that inevitably misclassify some shells.
    static func contractedLastLine(fromRawViewportText rawText: String) -> String? {
        for rawLine in rawText.components(separatedBy: "\n").reversed() {
            guard let normalized = normalizedLine(rawLine) else { continue }
            return normalized
        }
        return nil
    }

    /// Trims, strips control residue, and byte-bounds a raw viewport row.
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
