import AgentStudioIPCTransport
import Foundation
import Testing

@Suite("NDJSON frame codec")
struct NDJSONFrameCodecTests {
    @Test("emits complete newline-delimited frames across chunks")
    func emitsCompleteFramesAcrossChunks() throws {
        var decoder = NDJSONFrameDecoder(maxFrameBytes: 64)

        let first = try decoder.append(Data(#"{"id":"1"}"#.utf8))
        let second = try decoder.append(Data("\n{\"id\":\"2\"}\npartial".utf8))

        #expect(first.isEmpty)
        #expect(second == [#"{"id":"1"}"#, #"{"id":"2"}"#])
        #expect(decoder.pendingByteCount == "partial".utf8.count)
    }

    @Test("rejects frames over the byte limit before newline")
    func rejectsOversizedPendingFrame() throws {
        var decoder = NDJSONFrameDecoder(maxFrameBytes: 4)

        #expect(throws: NDJSONFrameError.self) {
            try decoder.append(Data("12345".utf8))
        }
    }

    @Test("rejects invalid utf8 frames")
    func rejectsInvalidUTF8Frames() throws {
        var decoder = NDJSONFrameDecoder(maxFrameBytes: 64)

        #expect(throws: NDJSONFrameError.self) {
            try decoder.append(Data([0xff, 0x0a]))
        }
    }

    @Test("encodes frames with a newline terminator")
    func encodesFramesWithNewlineTerminator() throws {
        let data = try NDJSONFrameEncoder.encode(#"{"id":"1"}"#, maxFrameBytes: 64)

        #expect(String(data: data, encoding: .utf8) == #"{"id":"1"}"# + "\n")
    }

    @Test("rejects encoded frames with embedded newlines")
    func rejectsEncodedFramesWithEmbeddedNewlines() throws {
        #expect(throws: NDJSONFrameError.self) {
            try NDJSONFrameEncoder.encode("first\nsecond", maxFrameBytes: 64)
        }
    }
}
