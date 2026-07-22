import CryptoKit
import Darwin
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
        guard case .available(let descriptor) = materialization.payload.availability else {
            Issue.record("Expected complete File metadata to issue a text descriptor")
            return
        }
        let reader = try await BridgePaneProductFileContentSource.openReadSession(
            .init(
                descriptor: descriptor,
                relativePath: relativePath,
                rootURL: directoryURL
            )
        )
        var assembledData = Data()
        while let chunk = try await reader.nextChunk(
            maximumByteCount: BridgeProductWireContract.maximumContentDataPayloadBytes
        ) {
            assembledData.append(chunk)
        }
        await reader.close()
        let assembledText = try #require(String(data: assembledData, encoding: .utf8))
        let assembledSHA256 = sha256Hex(assembledData)
        let reachesFinalLineCanary = assembledText.hasSuffix(Self.finalLineCanary)
        let bytesEqualIndependentSource = assembledData == sourceData

        // Assert
        #expect(descriptor.declaredByteLength == sourceData.count)
        #expect(descriptor.maximumBytes == sourceData.count)
        #expect(descriptor.window.maximumBytes == sourceData.count)
        #expect(descriptor.window.maximumLines == Self.sourceLineCount)
        #expect(descriptor.expectedSha256 == Self.sourceSHA256)
        #expect(materialization.payload.payloadByteCount == sourceData.count)
        #expect(materialization.payload.payloadLineCount == Self.sourceLineCount)
        #expect(materialization.payload.totalLineCount == Self.sourceLineCount)
        #expect(materialization.payload.truncationKind == .complete)
        #expect(materialization.payload.virtualizedExtentKind == .exactLineCount)
        #expect(!materialization.payload.endsMidLine)
        #expect(
            reachesFinalLineCanary
                && bytesEqualIndependentSource
                && assembledSHA256 == Self.sourceSHA256,
            "complete File product source must reach the final-line canary and equal independent source bytes; observed \(assembledData.count)/\(sourceData.count) bytes, sha256=\(assembledSHA256)"
        )
    }

    @Test("rejects a parent symlink swap between containment preflight and open")
    func rejectsParentSymlinkSwapBeforeOpen() async throws {
        // Arrange
        let fileManager = FileManager.default
        let containerURL = fileManager.temporaryDirectory
            .appending(path: "bridge-file-open-race-\(UUID().uuidString)")
        let rootURL = containerURL.appending(path: "worktree")
        let trustedDirectoryURL = rootURL.appending(path: "trusted")
        let displacedTrustedDirectoryURL = rootURL.appending(path: "trusted-original")
        let externalDirectoryURL = containerURL.appending(path: "external")
        let relativePath = "trusted/source.txt"
        let trustedData = Data("trusted-source".utf8)
        let externalData = Data("external-data!".utf8)
        #expect(trustedData.count == externalData.count)
        try fileManager.createDirectory(
            at: trustedDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: externalDirectoryURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: containerURL) }
        try trustedData.write(to: trustedDirectoryURL.appending(path: "source.txt"))
        try externalData.write(to: externalDirectoryURL.appending(path: "source.txt"))
        let materialization = try await BridgePaneProductFileContentSource.materialize(
            .init(
                relativePath: relativePath,
                rootURL: rootURL,
                row: BridgeWorktreeTreeRowMetadata(
                    rowId: "open-race-row-1",
                    path: relativePath,
                    name: "source.txt",
                    parentPath: "trusted",
                    depth: 1,
                    isDirectory: false,
                    fileId: "open-race-file-1",
                    sizeBytes: trustedData.count,
                    lineCount: 1,
                    changeStatus: nil
                ),
                source: try .init(
                    repoId: "00000000-0000-4000-8000-000000000001",
                    rootRevisionToken: "open-race-root-revision-1",
                    sourceCursor: "open-race-source-cursor-1",
                    sourceId: "open-race-source-1",
                    subscriptionGeneration: 1,
                    worktreeId: "00000000-0000-4000-8000-000000000002"
                )
            )
        )
        guard case .available(let descriptor) = materialization.payload.availability else {
            Issue.record("Expected the trusted source to issue a File descriptor")
            return
        }
        let openedDescriptorRecorder = OpenedFileDescriptorIdentityRecorder()

        // Act
        var rejected = false
        do {
            _ = try await BridgePaneProductFileContentSource.openReadSession(
                .init(
                    descriptor: descriptor,
                    relativePath: relativePath,
                    rootURL: rootURL
                ),
                beforeOpeningResolvedFile: { _ in
                    try FileManager.default.moveItem(
                        at: trustedDirectoryURL,
                        to: displacedTrustedDirectoryURL
                    )
                    try FileManager.default.createSymbolicLink(
                        at: trustedDirectoryURL,
                        withDestinationURL: externalDirectoryURL
                    )
                },
                afterOpeningFileDescriptor: { fileDescriptor in
                    openedDescriptorRecorder.record(fileDescriptor)
                }
            )
        } catch {
            rejected = true
        }

        // Assert
        #expect(rejected)
        #expect(
            try fileManager.destinationOfSymbolicLink(atPath: trustedDirectoryURL.path)
                == externalDirectoryURL.path
        )
        #expect(try Data(contentsOf: trustedDirectoryURL.appending(path: "source.txt")) == externalData)
        let openedDescriptor = try #require(openedDescriptorRecorder.value)
        expectDescriptorWasClosedOrReassigned(openedDescriptor)
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

private struct OpenedFileDescriptorIdentity {
    let device: dev_t
    let fileDescriptor: Int32
    let inode: ino_t
}

private func expectDescriptorWasClosedOrReassigned(
    _ openedDescriptor: OpenedFileDescriptorIdentity
) {
    var descriptorStatusAfterRejection = stat()
    let descriptorStatusResult = fstat(
        openedDescriptor.fileDescriptor,
        &descriptorStatusAfterRejection
    )
    let descriptorStatusErrno = errno
    if descriptorStatusResult == 0 {
        #expect(
            descriptorStatusAfterRejection.st_dev != openedDescriptor.device
                || descriptorStatusAfterRejection.st_ino != openedDescriptor.inode,
            "the rejected source descriptor must be closed; a reused descriptor number may remain valid only when it refers to a different file identity"
        )
    } else {
        #expect(descriptorStatusResult == -1)
        #expect(descriptorStatusErrno == EBADF)
    }
}

private final class OpenedFileDescriptorIdentityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValue: OpenedFileDescriptorIdentity?

    var value: OpenedFileDescriptorIdentity? {
        lock.withLock { recordedValue }
    }

    func record(_ fileDescriptor: Int32) {
        var openedDescriptorStatus = stat()
        let statusResult = fstat(fileDescriptor, &openedDescriptorStatus)
        lock.withLock {
            guard statusResult == 0 else {
                recordedValue = nil
                return
            }
            recordedValue = OpenedFileDescriptorIdentity(
                device: openedDescriptorStatus.st_dev,
                fileDescriptor: fileDescriptor,
                inode: openedDescriptorStatus.st_ino
            )
        }
    }
}
