import Foundation
import Testing

@testable import AgentStudioCore

/// Program Design item 3, "the marker": `ColdStartObserver`'s handoff check
/// reads this exact `sysctl(CTL_KERN, KERN_PROCARGS2, pid)` wire format.
/// These synthetic buffers match the layout confirmed empirically against a
/// live macOS process (`argc`, then the exec path, then argc argv strings,
/// then the environment strings, each NUL-terminated with NUL padding
/// between sections) -- this suite proves the parser against that shape
/// without needing a real process or touching code-signing concerns.
@Suite("Process arguments buffer parser")
struct ProcessArgumentsBufferParserTests {
    @Test("finds the marker among several environment entries")
    func findsTheMarkerAmongSeveralEnvironmentEntries() {
        let buffer = makeBuffer(
            execPath: "/bin/zsh",
            argv: ["-zsh", "-i", "-l"],
            envp: ["PATH=/usr/bin:/bin", "AGENTSTUDIO_RESTORE_ATTEMPT=01a0f106-abc", "HOME=/Users/test"]
        )

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == "01a0f106-abc")
    }

    @Test("a missing variable among a present, non-empty environment returns nil")
    func missingVariableReturnsNil() {
        let buffer = makeBuffer(execPath: "/bin/zsh", argv: ["-zsh"], envp: ["PATH=/usr/bin"])

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == nil)
    }

    @Test("no environment section at all (the CS_RESTRICT / omitted-env shape) returns nil for the marker")
    func omittedEnvironmentReturnsNilForTheMarker() {
        // Matches the exact shape observed for a freshly-exec'd /bin/zsh -i -l
        // when the kernel omits envp: argc, exec path, argv, buffer ends.
        let buffer = makeBuffer(execPath: "/bin/zsh", argv: ["-zsh", "-i", "-l"], envp: [])

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == nil)
        #expect(!ProcessArgumentsBufferParser.environmentSectionIsPresent(in: buffer))
    }

    @Test("a present environment section is reported present even without the marker")
    func presentEnvironmentSectionIsReportedPresent() {
        let buffer = makeBuffer(execPath: "/bin/zsh", argv: ["-zsh"], envp: ["PATH=/usr/bin"])

        #expect(ProcessArgumentsBufferParser.environmentSectionIsPresent(in: buffer))
    }

    @Test("a buffer shorter than the argc field returns nil, never crashes")
    func tooShortForArgcReturnsNil() {
        let buffer: [UInt8] = [0, 0]

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == nil)
        #expect(!ProcessArgumentsBufferParser.environmentSectionIsPresent(in: buffer))
    }

    @Test("argc claiming more argv strings than the buffer actually holds returns nil, never reads out of bounds")
    func truncatedArgvReturnsNil() {
        // argc = 5, but only the exec path follows -- no argv strings, no
        // terminator for a 5th argument the buffer never contains.
        var buffer = withUnsafeBytes(of: Int32(5).littleEndian) { Array($0) }
        buffer.append(contentsOf: Array("/bin/zsh".utf8))
        buffer.append(0)

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == nil)
    }

    @Test("a negative argc is rejected rather than looping forever or reading out of bounds")
    func negativeArgcReturnsNil() {
        var buffer = withUnsafeBytes(of: Int32(-1).littleEndian) { Array($0) }
        buffer.append(contentsOf: Array("/bin/zsh\0".utf8))

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == nil)
    }

    @Test("multiple NUL padding bytes between sections are skipped correctly")
    func multipleNULPaddingBytesAreSkipped() {
        var buffer = withUnsafeBytes(of: Int32(1).littleEndian) { Array($0) }
        buffer.append(contentsOf: Array("/bin/zsh\0".utf8))
        buffer.append(contentsOf: [0, 0, 0, 0, 0])  // extra alignment padding, as observed live
        buffer.append(contentsOf: Array("-zsh\0".utf8))
        buffer.append(contentsOf: [0, 0])
        buffer.append(contentsOf: Array("AGENTSTUDIO_RESTORE_ATTEMPT=marker-value\0".utf8))

        let value = ProcessArgumentsBufferParser.environmentValue(named: "AGENTSTUDIO_RESTORE_ATTEMPT", in: buffer)

        #expect(value == "marker-value")
    }

    // MARK: - Helpers

    /// Builds a synthetic `KERN_PROCARGS2` buffer: argc, exec path (NUL
    /// then one padding NUL), argv strings (NUL-terminated), one padding
    /// NUL, then envp strings (NUL-terminated). `envp` empty reproduces the
    /// omitted-environment shape exactly (the buffer simply ends after argv).
    private func makeBuffer(execPath: String, argv: [String], envp: [String]) -> [UInt8] {
        var buffer = withUnsafeBytes(of: Int32(argv.count).littleEndian) { Array($0) }
        buffer.append(contentsOf: Array(execPath.utf8))
        buffer.append(0)
        buffer.append(0)  // alignment padding after the exec path, as observed live
        for argument in argv {
            buffer.append(contentsOf: Array(argument.utf8))
            buffer.append(0)
        }
        guard !envp.isEmpty else { return buffer }
        buffer.append(0)  // padding between argv and envp
        for entry in envp {
            buffer.append(contentsOf: Array(entry.utf8))
            buffer.append(0)
        }
        return buffer
    }
}
