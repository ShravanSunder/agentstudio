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

    /// Doubling the payload must roughly double the work. Before the decoder
    /// carried its scan offset across appends it searched the whole buffer
    /// again for every chunk, and this ratio measured about four.
    @Test("scanning a chunked frame costs linear, not quadratic, work")
    func chunkedFrameScanningIsLinear() throws {
        let singleMebibyte = try fastestChunkedDecodeSeconds(payloadBytes: 1_048_576)
        let doubleMebibyte = try fastestChunkedDecodeSeconds(payloadBytes: 2 * 1_048_576)

        #expect(
            doubleMebibyte < singleMebibyte * 3,
            "1 MiB \(singleMebibyte)s, 2 MiB \(doubleMebibyte)s"
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

    /// The fastest of three runs, because the minimum is the least noisy
    /// statistic for a timing comparison and this case only needs the growth
    /// rate, not an absolute number.
    private func fastestChunkedDecodeSeconds(payloadBytes: Int) throws -> Double {
        let frame = Data((String(repeating: "a", count: payloadBytes) + "\n").utf8)
        var fastest = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            var decoder = NDJSONFrameDecoder(maxFrameBytes: 8 * 1_048_576)
            let started = ContinuousClock.now
            _ = try appendInChunks(frame, to: &decoder)
            let elapsed = ContinuousClock.now - started
            let attosecondsPerSecond = 1_000_000_000_000_000_000.0
            let seconds =
                Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / attosecondsPerSecond
            fastest = min(fastest, seconds)
        }
        return fastest
    }
}
