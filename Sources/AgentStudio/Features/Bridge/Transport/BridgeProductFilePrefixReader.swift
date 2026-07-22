import CryptoKit
import Foundation

struct BridgeProductFilePrefix: Equatable, Sendable {
    let data: Data
    let didReachEnd: Bool
    let endsMidLine: Bool
    let endsWithNewline: Bool
    let isBinary: Bool
    let isValidUTF8: Bool
    let lineCount: Int
    let sha256: String
    let truncationKind: BridgeProductFileTruncationKind
}

enum BridgeProductFilePrefixReader {
    private struct IncompleteUTF8Scalar {
        let expectedByteCount: Int
        let retainedByteCount: Int
    }

    static func read(_ fileURL: URL) throws -> BridgeProductFilePrefix {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let maximumBytes = BridgeProductWireContract.maximumContentBytes
        let maximumLines = BridgeProductWireContract.maximumContentLines
        var data = Data(capacity: min(maximumBytes, 128 * 1024))
        var bytesAfterBoundary = Data()
        var sourceHasMoreBytes = false
        var isBinary = false
        var newlineCount = 0
        var reachedByteLimit = false
        var reachedLineLimit = false

        while !reachedByteLimit, !reachedLineLimit {
            try Task.checkCancellation()
            let readCount = min(64 * 1024, maximumBytes - data.count)
            guard let chunk = try fileHandle.read(upToCount: readCount), !chunk.isEmpty else {
                break
            }
            for (index, byte) in chunk.enumerated() {
                if byte == 0 { isBinary = true }
                data.append(byte)
                if byte == UInt8(ascii: "\n") {
                    newlineCount += 1
                }
                let reachedCurrentLineLimit = newlineCount == maximumLines
                let reachedCurrentByteLimit = data.count == maximumBytes
                if reachedCurrentLineLimit || reachedCurrentByteLimit {
                    reachedLineLimit = reachedCurrentLineLimit
                    reachedByteLimit = reachedCurrentByteLimit
                    bytesAfterBoundary = boundaryLookahead(in: chunk, afterOffset: index)
                    break
                }
            }
        }
        if reachedByteLimit || reachedLineLimit, bytesAfterBoundary.isEmpty {
            bytesAfterBoundary = try fileHandle.read(upToCount: 3) ?? Data()
        }
        sourceHasMoreBytes = !bytesAfterBoundary.isEmpty
        let utf8Result = canonicalUTF8Prefix(
            data,
            bytesAfterBoundary: reachedByteLimit && sourceHasMoreBytes ? bytesAfterBoundary : nil
        )
        data = utf8Result.data
        let endsWithNewline = data.last == UInt8(ascii: "\n")
        let lineCount = data.isEmpty ? 0 : newlineCount + (endsWithNewline ? 0 : 1)
        return BridgeProductFilePrefix(
            data: data,
            didReachEnd: !sourceHasMoreBytes,
            endsMidLine: sourceHasMoreBytes && !endsWithNewline,
            endsWithNewline: endsWithNewline,
            isBinary: isBinary,
            isValidUTF8: utf8Result.isValid,
            lineCount: lineCount,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            truncationKind: truncationKind(
                sourceHasMoreBytes: sourceHasMoreBytes,
                reachedByteLimit: reachedByteLimit,
                reachedLineLimit: reachedLineLimit,
                lineCount: lineCount
            )
        )
    }

    private static func truncationKind(
        sourceHasMoreBytes: Bool,
        reachedByteLimit: Bool,
        reachedLineLimit: Bool,
        lineCount: Int
    ) -> BridgeProductFileTruncationKind {
        guard sourceHasMoreBytes else { return .complete }
        if reachedByteLimit, lineCount == BridgeProductWireContract.maximumContentLines {
            return .both
        }
        return reachedLineLimit ? .lineLimit : .byteLimit
    }

    private static func canonicalUTF8Prefix(
        _ data: Data,
        bytesAfterBoundary: Data?
    ) -> (data: Data, isValid: Bool) {
        guard String(data: data, encoding: .utf8) == nil else {
            return (data, true)
        }
        guard let bytesAfterBoundary,
            let incompleteScalar = incompleteUTF8Scalar(data),
            bytesAfterBoundary.count
                >= incompleteScalar.expectedByteCount - incompleteScalar.retainedByteCount
        else {
            return (data, false)
        }
        let requiredContinuationByteCount =
            incompleteScalar.expectedByteCount - incompleteScalar.retainedByteCount
        var boundaryScalar = Data(data.suffix(incompleteScalar.retainedByteCount))
        boundaryScalar.append(bytesAfterBoundary.prefix(requiredContinuationByteCount))
        guard String(data: boundaryScalar, encoding: .utf8) != nil else {
            return (data, false)
        }
        let candidate = data.dropLast(incompleteScalar.retainedByteCount)
        return (Data(candidate), String(data: candidate, encoding: .utf8) != nil)
    }

    private static func incompleteUTF8Scalar(_ data: Data) -> IncompleteUTF8Scalar? {
        guard let finalByte = data.last, finalByte >= 0x80 else { return nil }
        var scalarStart = data.count - 1
        while scalarStart > 0,
            (0x80...0xbf).contains(data[scalarStart]),
            data.count - scalarStart < 4
        {
            scalarStart -= 1
        }
        let leadingByte = data[scalarStart]
        let expectedByteCount: Int
        switch leadingByte {
        case 0xc2...0xdf: expectedByteCount = 2
        case 0xe0...0xef: expectedByteCount = 3
        case 0xf0...0xf4: expectedByteCount = 4
        default: return nil
        }
        let availableByteCount = data.count - scalarStart
        guard availableByteCount < expectedByteCount else { return nil }
        let continuationBytes = data[scalarStart...].dropFirst()
        guard continuationBytes.allSatisfy({ (0x80...0xbf).contains($0) }),
            validPartialScalarPrefix(leadingByte: leadingByte, continuationBytes: continuationBytes)
        else { return nil }
        return IncompleteUTF8Scalar(
            expectedByteCount: expectedByteCount,
            retainedByteCount: availableByteCount
        )
    }

    private static func boundaryLookahead(in chunk: Data, afterOffset offset: Int) -> Data {
        guard offset + 1 < chunk.count else { return Data() }
        let nextIndex = chunk.index(chunk.startIndex, offsetBy: offset + 1)
        return Data(chunk[nextIndex...].prefix(3))
    }

    private static func validPartialScalarPrefix(
        leadingByte: UInt8,
        continuationBytes: Data.SubSequence
    ) -> Bool {
        guard let secondByte = continuationBytes.first else { return true }
        switch leadingByte {
        case 0xe0: return (0xa0...0xbf).contains(secondByte)
        case 0xed: return (0x80...0x9f).contains(secondByte)
        case 0xf0: return (0x90...0xbf).contains(secondByte)
        case 0xf4: return (0x80...0x8f).contains(secondByte)
        default: return true
        }
    }
}
