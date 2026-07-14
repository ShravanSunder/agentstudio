import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge File complete content")
struct BridgeFileCompleteContentTests {
    private static let sourceByteCount = 2_097_217
    private static let sourceLineCount = 10_001
    private static let sourceSHA256 =
        "c15344b0a2aabc7a0f63ddda2d79d604bce142de7228fc3f36162db775a6cbda"
    private static let finalLineCanary =
        "line-10001: __BRIDGE_FILE_COMPLETE_FINAL_CANARY_8B3F27D1__ λ😀"
    private static let regularCRLFLineByteCount = 209

    @Test("materializes exact complete text beyond both legacy File prefix limits")
    func materializesExactCompleteTextBeyondLegacyLimits() async throws {
        // Arrange
        let sourceText = makeCompleteFileSourceText()
        let sourceData = Data(sourceText.utf8)
        let decodedSourceText = try #require(String(data: sourceData, encoding: .utf8))
        #expect(sourceData.count == Self.sourceByteCount)
        #expect(sourceData.count > BridgeProductWireContract.maximumContentBytes)
        #expect(logicalLineCount(sourceData) == Self.sourceLineCount)
        #expect(Self.sourceLineCount > BridgeProductWireContract.maximumContentLines)
        #expect(sourceData.filter { $0 == UInt8(ascii: "\r") }.count == 10_000)
        #expect(sourceData.filter { $0 == UInt8(ascii: "\n") }.count == 10_000)
        #expect(decodedSourceText == sourceText)
        #expect(sourceText.hasSuffix(Self.finalLineCanary))
        #expect(sourceText.components(separatedBy: Self.finalLineCanary).count == 2)
        #expect(sha256Hex(sourceData) == Self.sourceSHA256)

        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-file-complete-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let relativePath = "complete-file.txt"
        try sourceData.write(to: directoryURL.appending(path: relativePath))

        // Act
        let materialization = try await BridgePaneProductFileContentSource.materialize(
            .init(
                relativePath: relativePath,
                rootURL: directoryURL,
                row: BridgeWorktreeTreeRowMetadata(
                    rowId: "complete-file-row-1",
                    path: relativePath,
                    name: relativePath,
                    parentPath: nil,
                    depth: 0,
                    isDirectory: false,
                    fileId: "complete-file-1",
                    sizeBytes: sourceData.count,
                    lineCount: Self.sourceLineCount,
                    changeStatus: nil
                ),
                source: try .init(
                    repoId: "00000000-0000-4000-8000-000000000001",
                    rootRevisionToken: "complete-file-root-revision-1",
                    sourceCursor: "complete-file-source-cursor-1",
                    sourceId: "complete-file-source-1",
                    subscriptionGeneration: 1,
                    worktreeId: "00000000-0000-4000-8000-000000000002"
                )
            )
        )
        let body = try #require(materialization.body)
        let assembledText = try #require(String(data: body.data, encoding: .utf8))
        let assembledSHA256 = sha256Hex(body.data)
        let reachesFinalLineCanary = assembledText.hasSuffix(Self.finalLineCanary)
        let bytesEqualIndependentSource = body.data == sourceData

        // Assert
        #expect(
            body.endOfSource
                && reachesFinalLineCanary
                && bytesEqualIndependentSource
                && assembledSHA256 == Self.sourceSHA256,
            "complete File product source must reach the final-line canary and equal independent source bytes; observed \(body.data.count)/\(sourceData.count) bytes, endOfSource=\(body.endOfSource), sha256=\(assembledSHA256)"
        )
    }

    private func makeCompleteFileSourceText() -> String {
        let boundaryLineByteCount =
            BridgeProductWireContract.maximumContentBytes
            - (BridgeProductWireContract.maximumContentLines - 1)
            * Self.regularCRLFLineByteCount
        var sourceText = String()
        sourceText.reserveCapacity(Self.sourceByteCount)
        for lineNumber in 1..<BridgeProductWireContract.maximumContentLines {
            sourceText.append(
                makeExactCRLFLine(
                    prefix: "line-\(String(format: "%05d", lineNumber)): λ😀 ",
                    totalByteCount: Self.regularCRLFLineByteCount
                )
            )
        }
        sourceText.append(
            makeExactCRLFLine(
                prefix: "line-10000: boundary λ😀 ",
                totalByteCount: boundaryLineByteCount
            )
        )
        sourceText.append(Self.finalLineCanary)
        return sourceText
    }

    private func makeExactCRLFLine(prefix: String, totalByteCount: Int) -> String {
        let fillerByteCount = totalByteCount - Data(prefix.utf8).count - 2
        let line = "\(prefix)\(String(repeating: "x", count: fillerByteCount))\r\n"
        #expect(Data(line.utf8).count == totalByteCount)
        return line
    }

    private func logicalLineCount(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let newlineCount = data.filter { $0 == UInt8(ascii: "\n") }.count
        return newlineCount + (data.last == UInt8(ascii: "\n") ? 0 : 1)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
