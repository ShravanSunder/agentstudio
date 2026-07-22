import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product File prefix reader")
struct BridgeProductFilePrefixReaderTests {
    @Test("empty, LF, CRLF, and final partial line counts are canonical")
    func canonicalLineCounts() throws {
        // Arrange
        let cases: [(Data, Int, Bool)] = [
            (Data(), 0, false),
            (Data("a\n".utf8), 1, true),
            (Data("a\nb".utf8), 2, false),
            (Data("a\r\nb\r\n".utf8), 2, true),
        ]

        // Act
        let prefixes = try cases.map { try readPrefix($0.0) }

        // Assert
        for (index, prefix) in prefixes.enumerated() {
            #expect(prefix.lineCount == cases[index].1)
            #expect(prefix.endsWithNewline == cases[index].2)
            #expect(prefix.didReachEnd)
            #expect(prefix.truncationKind == .complete)
            #expect(!prefix.endsMidLine)
            #expect(prefix.isValidUTF8)
        }
    }

    @Test("line limit stops after the ten-thousandth terminating LF")
    func lineLimitStopsAfterTerminatingLF() throws {
        // Arrange
        let expectedPrefix = Data(
            String(repeating: "a\n", count: BridgeProductWireContract.maximumContentLines).utf8
        )
        var source = expectedPrefix
        source.append(Data("tail".utf8))

        // Act
        let prefix = try readPrefix(source)

        // Assert
        #expect(prefix.data == expectedPrefix)
        #expect(prefix.lineCount == BridgeProductWireContract.maximumContentLines)
        #expect(prefix.truncationKind == .lineLimit)
        #expect(prefix.endsWithNewline)
        #expect(!prefix.endsMidLine)
        #expect(!prefix.didReachEnd)
    }

    @Test("byte limit backs up over an incomplete UTF-8 scalar")
    func byteLimitBacksUpOverIncompleteScalar() throws {
        // Arrange
        let retainedByteCount = BridgeProductWireContract.maximumContentBytes - 2
        var source = Data(repeating: UInt8(ascii: "a"), count: retainedByteCount)
        source.append(contentsOf: [0xe2, 0x82, 0xac, UInt8(ascii: "b")])

        // Act
        let prefix = try readPrefix(source)

        // Assert
        #expect(prefix.data == Data(repeating: UInt8(ascii: "a"), count: retainedByteCount))
        #expect(prefix.lineCount == 1)
        #expect(prefix.truncationKind == .byteLimit)
        #expect(prefix.endsMidLine)
        #expect(!prefix.endsWithNewline)
        #expect(prefix.isValidUTF8)
    }

    @Test("byte and line limits can bind the same partial final line")
    func byteAndLineLimitsBindPartialFinalLine() throws {
        // Arrange
        var source = Data(
            String(
                repeating: "a\n",
                count: BridgeProductWireContract.maximumContentLines - 1
            ).utf8
        )
        source.append(
            Data(
                repeating: UInt8(ascii: "a"),
                count: BridgeProductWireContract.maximumContentBytes - source.count + 1
            )
        )

        // Act
        let prefix = try readPrefix(source)

        // Assert
        #expect(prefix.data.count == BridgeProductWireContract.maximumContentBytes)
        #expect(prefix.lineCount == BridgeProductWireContract.maximumContentLines)
        #expect(prefix.truncationKind == .both)
        #expect(prefix.endsMidLine)
        #expect(!prefix.endsWithNewline)
    }

    @Test("byte and line limits both bind when the final byte is the ten-thousandth LF")
    func byteAndLineLimitsBindSameTerminatingLF() throws {
        // Arrange
        var source = Data(
            String(
                repeating: "a\n",
                count: BridgeProductWireContract.maximumContentLines - 1
            ).utf8
        )
        source.append(
            Data(
                repeating: UInt8(ascii: "a"),
                count: BridgeProductWireContract.maximumContentBytes - source.count - 1
            )
        )
        source.append(UInt8(ascii: "\n"))
        source.append(UInt8(ascii: "b"))

        // Act
        let prefix = try readPrefix(source)

        // Assert
        #expect(prefix.data.count == BridgeProductWireContract.maximumContentBytes)
        #expect(prefix.lineCount == BridgeProductWireContract.maximumContentLines)
        #expect(prefix.truncationKind == .both)
        #expect(!prefix.endsMidLine)
        #expect(prefix.endsWithNewline)
    }

    @Test("NUL is binary and malformed UTF-8 is never replacement-decoded")
    func classifiesBinaryAndUnsupportedEncoding() throws {
        // Arrange
        let nulSource = Data([UInt8(ascii: "a"), 0, UInt8(ascii: "b")])
        let malformedSource = Data([0xe0, 0x80, UInt8(ascii: "a")])
        var malformedAtByteLimit = Data(
            repeating: UInt8(ascii: "a"),
            count: BridgeProductWireContract.maximumContentBytes - 2
        )
        malformedAtByteLimit.append(contentsOf: [0xe0, 0x80, UInt8(ascii: "a")])
        var incompleteAtExactEnd = Data(
            repeating: UInt8(ascii: "a"),
            count: BridgeProductWireContract.maximumContentBytes - 2
        )
        incompleteAtExactEnd.append(contentsOf: [0xe2, 0x82])
        var invalidAcrossBoundary = Data(
            repeating: UInt8(ascii: "a"),
            count: BridgeProductWireContract.maximumContentBytes - 1
        )
        invalidAcrossBoundary.append(contentsOf: [0xe2, 0x28, 0xa1])

        // Act
        let binaryPrefix = try readPrefix(nulSource)
        let malformedPrefix = try readPrefix(malformedSource)
        let malformedBoundaryPrefix = try readPrefix(malformedAtByteLimit)
        let incompleteEndPrefix = try readPrefix(incompleteAtExactEnd)
        let invalidBoundaryPrefix = try readPrefix(invalidAcrossBoundary)

        // Assert
        #expect(binaryPrefix.isBinary)
        #expect(!malformedPrefix.isValidUTF8)
        #expect(!malformedBoundaryPrefix.isValidUTF8)
        #expect(!incompleteEndPrefix.isValidUTF8)
        #expect(!invalidBoundaryPrefix.isValidUTF8)
    }

    private func readPrefix(_ data: Data) throws -> BridgeProductFilePrefix {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-product-prefix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appending(path: "fixture.txt")
        try data.write(to: fileURL)
        return try BridgeProductFilePrefixReader.read(fileURL)
    }
}
