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

    @Test("a large frame arriving in chunks decodes once and leaves nothing pending")
    func largeChunkedFrameDecodesExactly() throws {
        let payload = String(repeating: "a", count: 2 * 1_048_576)
        var decoder = NDJSONFrameDecoder(maxFrameBytes: 8 * 1_048_576)

        let frames = try appendInChunks(Data((payload + "\n").utf8), to: &decoder)

        #expect(frames == [payload])
        #expect(decoder.pendingByteCount == 0)
    }

    /// Each byte of a chunked frame must be looked at once.
    ///
    /// This used to compare how long a 1 MiB decode took against a 2 MiB one and
    /// demand the ratio stay under three, which asks a shared CI machine to be a
    /// stopwatch. The decoder now counts the bytes it examines, so the same
    /// claim is a fact about work done rather than about elapsed time.
    ///
    /// The allowance is one chunk: the search that finds the newline re-examines
    /// nothing, but the final chunk is scanned in full before the terminator
    /// turns up. Rescanning the whole buffer per chunk, which is what the offset
    /// carried across appends prevents, would examine roughly sixty times the
    /// payload here, far past `frame.count * 8`.
    @Test("scanning a chunked frame examines each byte once")
    func chunkedFrameScanningExaminesEachByteOnce() throws {
        // Arrange
        let chunkBytes = 16_384
        let payload = String(repeating: "a", count: 2 * 1_048_576)
        let frame = Data((payload + "\n").utf8)
        var decoder = NDJSONFrameDecoder(maxFrameBytes: 8 * 1_048_576)

        // Act
        let frames = try appendInChunks(frame, to: &decoder, chunkBytes: chunkBytes)

        // Assert
        #expect(frames == [payload])
        #expect(
            decoder.scannedByteCount <= frame.count + chunkBytes,
            "examined \(decoder.scannedByteCount) bytes for a \(frame.count) byte frame"
        )
    }

    @Test("the frame ceiling still applies to a frame assembled from chunks")
    func chunkedFrameStillHonoursTheCeiling() throws {
        var decoder = NDJSONFrameDecoder(maxFrameBytes: 32_768)
        let payload = String(repeating: "a", count: 65_536)

        let error = #expect(throws: NDJSONFrameError.self) {
            _ = try appendInChunks(Data((payload + "\n").utf8), to: &decoder)
        }

        #expect(error?.reason == .frameTooLarge)
        // The ceiling trips on the unterminated buffer, so it reports what was
        // held rather than a frame length it never saw.
        #expect(decoder.pendingByteCount == 0)
    }

    @Test("rejects encoded frames with embedded newlines")
    func rejectsEncodedFramesWithEmbeddedNewlines() throws {
        #expect(throws: NDJSONFrameError.self) {
            try NDJSONFrameEncoder.encode("first\nsecond", maxFrameBytes: 64)
        }
    }

    /// Feeds one buffer the way a socket delivers it.
    private func appendInChunks(
        _ data: Data,
        to decoder: inout NDJSONFrameDecoder,
        chunkBytes: Int = 16_384
    ) throws -> [String] {
        var frames: [String] = []
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = data.index(offset, offsetBy: chunkBytes, limitedBy: data.endIndex) ?? data.endIndex
            frames += try decoder.append(data[offset..<end])
            offset = end
        }
        return frames
    }
}
