import Foundation

/// Parses the `sysctl(CTL_KERN, KERN_PROCARGS2, pid)` buffer format, the
/// wire shape `ColdStartObserver`'s handoff check reads to find
/// `AGENTSTUDIO_RESTORE_ATTEMPT` (Program Design item 3, "the marker").
///
/// Layout, confirmed empirically against a live macOS process (a native
/// `Int32` argc, then the exec path, then argc argv strings, then the
/// environment strings, every string NUL-terminated with NUL padding
/// between sections):
///
/// ```
/// [argc: Int32][exec path\0][\0 padding][argv[0]\0]...[argv[argc-1]\0][\0 padding][envp[0]\0]...
/// ```
///
/// Bounds are never trusted implicitly: a truncated buffer or a missing
/// terminator ends parsing early rather than reading past the buffer, since
/// this reads memory the kernel filled for an external, unrelated process.
enum ProcessArgumentsBufferParser {
    /// Returns the value of the first `name=<value>` environment entry, or
    /// `nil` when the buffer is malformed, too short, or the environment
    /// section is absent or does not contain `name`.
    ///
    /// An empty environment section is not distinguished from a malformed
    /// buffer here — both return `nil`. Callers that need to tell
    /// "no environment was returned at all" apart from "returned, but this
    /// variable wasn't in it" (`ColdStartUnobservableReason
    /// .environmentOmitted`) use `environmentSectionIsPresent(in:)` first.
    static func environmentValue(named name: String, in buffer: [UInt8]) -> String? {
        guard let environmentStart = environmentSectionStart(in: buffer) else { return nil }
        let prefix = "\(name)="
        var offset = environmentStart
        while offset < buffer.count {
            guard let entryEnd = nulTerminatedStringEnd(in: buffer, from: offset) else { break }
            guard let entry = String(bytes: buffer[offset..<(entryEnd - 1)], encoding: .utf8) else {
                offset = entryEnd
                continue
            }
            if entry.hasPrefix(prefix) {
                return String(entry.dropFirst(prefix.count))
            }
            offset = entryEnd
        }
        return nil
    }

    /// True when the buffer has at least one byte beyond the argv section —
    /// XNU either includes the full environment or omits it entirely
    /// (`ColdStartUnobservableReason.environmentOmitted`'s CS_RESTRICT
    /// case), so "the environment section is present but empty" and "no
    /// process actually has zero environment variables" are not outcomes
    /// this needs to tell apart.
    static func environmentSectionIsPresent(in buffer: [UInt8]) -> Bool {
        guard let environmentStart = environmentSectionStart(in: buffer) else { return false }
        return environmentStart < buffer.count
    }

    /// Walks past `[argc][exec path\0][padding][argv strings][padding]` and
    /// returns the offset where the environment section would begin. `nil`
    /// when the buffer is too short or a string is missing its terminator
    /// before the buffer ends (a malformed read, not a valid empty section).
    private static func environmentSectionStart(in buffer: [UInt8]) -> Int? {
        guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
        let argumentCount = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: Int32.self)
        }
        guard argumentCount >= 0 else { return nil }
        var offset = MemoryLayout<Int32>.size
        guard let execPathEnd = nulTerminatedStringEnd(in: buffer, from: offset) else { return nil }
        offset = skipNULPadding(in: buffer, from: execPathEnd)
        for _ in 0..<argumentCount {
            guard let argumentEnd = nulTerminatedStringEnd(in: buffer, from: offset) else { return nil }
            offset = argumentEnd
        }
        return skipNULPadding(in: buffer, from: offset)
    }

    /// The offset one past the first NUL at or after `start`, or `nil` when
    /// none is found before the buffer ends.
    private static func nulTerminatedStringEnd(in buffer: [UInt8], from start: Int) -> Int? {
        var index = start
        while index < buffer.count {
            if buffer[index] == 0 { return index + 1 }
            index += 1
        }
        return nil
    }

    private static func skipNULPadding(in buffer: [UInt8], from start: Int) -> Int {
        var index = start
        while index < buffer.count, buffer[index] == 0 {
            index += 1
        }
        return index
    }
}
