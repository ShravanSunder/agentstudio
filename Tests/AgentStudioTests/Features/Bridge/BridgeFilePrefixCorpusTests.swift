import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge File prefix shared corpus")
struct BridgeFilePrefixCorpusTests {
    private static let corpusRelativePath =
        "Tests/BridgeContractFixtures/valid/bridge-file-prefix-corpus.json"
    private static let mirroredCorpusRelativePath =
        "BridgeWeb/src/test-fixtures/bridge-contract-fixtures/valid/bridge-file-prefix-corpus.json"
    private static let frozenCorpusSHA256 =
        "6e78b5ffce449348b3ff14e5913d9b46b0f72f8fdc3544ff95e68bfc7b69f274"

    @Test("mirrored Swift and TypeScript corpus bytes have one frozen identity")
    func mirroredCorpusBytesHaveFrozenIdentity() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))

        // Act
        let swiftBytes = try Data(contentsOf: projectRoot.appending(path: Self.corpusRelativePath))
        let typeScriptBytes = try Data(
            contentsOf: projectRoot.appending(path: Self.mirroredCorpusRelativePath)
        )
        let observedSHA256 = sha256Hex(swiftBytes)

        // Assert
        #expect(swiftBytes == typeScriptBytes)
        #expect(observedSHA256 == Self.frozenCorpusSHA256)
    }

    @Test("native prefix reader matches every shared byte and boundary oracle")
    func nativePrefixReaderMatchesSharedCorpus() async throws {
        // Arrange
        let corpus = try loadCorpus()
        #expect(corpus.schemaVersion == 1)
        #expect(corpus.maximumPayloadBytes == BridgeProductWireContract.maximumContentBytes)
        #expect(corpus.maximumPayloadLines == BridgeProductWireContract.maximumContentLines)
        #expect(Set(corpus.cases.map(\.name)).count == corpus.cases.count)

        // Act
        let observedCases = try corpus.cases.map { fixtureCase in
            let source = try fixtureCase.sourceData()
            let prefix = try readPrefix(source, caseName: fixtureCase.name)
            return (fixtureCase, source, prefix)
        }

        // Assert
        for (fixtureCase, source, prefix) in observedCases {
            let expected = fixtureCase.expectedReader
            #expect(prefix.data.count == expected.payloadByteCount, Comment(rawValue: fixtureCase.name))
            #expect(prefix.lineCount == expected.payloadLineCount, Comment(rawValue: fixtureCase.name))
            #expect(prefix.didReachEnd == expected.didReachEnd, Comment(rawValue: fixtureCase.name))
            #expect(prefix.endsMidLine == expected.endsMidLine, Comment(rawValue: fixtureCase.name))
            #expect(prefix.endsWithNewline == expected.endsWithNewline, Comment(rawValue: fixtureCase.name))
            #expect(prefix.isBinary == expected.isBinary, Comment(rawValue: fixtureCase.name))
            #expect(prefix.isValidUTF8 == expected.isValidUTF8, Comment(rawValue: fixtureCase.name))
            #expect(prefix.truncationKind == expected.truncationKind, Comment(rawValue: fixtureCase.name))
            #expect(prefix.data.count <= corpus.maximumPayloadBytes)
            #expect(prefix.lineCount <= corpus.maximumPayloadLines)
            if let expectedSHA256 = expected.payloadSHA256 {
                #expect(prefix.sha256 == expectedSHA256, Comment(rawValue: fixtureCase.name))
                #expect(sha256Hex(prefix.data) == expectedSHA256, Comment(rawValue: fixtureCase.name))
            }
            try await assertProductAvailability(fixtureCase, source: source, prefix: prefix)
        }
    }

    private func assertProductAvailability(
        _ fixtureCase: BridgeFilePrefixCorpusCase,
        source: Data,
        prefix: BridgeProductFilePrefix
    ) async throws {
        switch fixtureCase.productAvailability {
        case .available:
            #expect(!prefix.isBinary, Comment(rawValue: fixtureCase.name))
            #expect(prefix.isValidUTF8, Comment(rawValue: fixtureCase.name))
            #expect(fixtureCase.expectedReader.payloadSHA256 != nil)
            #expect(prefix.data.count <= source.count)
        case .binary:
            #expect(prefix.isBinary, Comment(rawValue: fixtureCase.name))
            let materialization = try await materialize(source, caseName: fixtureCase.name)
            assertBodylessMaterialization(materialization, expectedAvailability: .binary)
        case .unsupportedEncoding:
            #expect(!prefix.isValidUTF8, Comment(rawValue: fixtureCase.name))
            let materialization = try await materialize(source, caseName: fixtureCase.name)
            assertBodylessMaterialization(
                materialization,
                expectedAvailability: .unavailable(.unsupportedEncoding)
            )
        }
    }

    private func assertBodylessMaterialization(
        _ materialization: BridgePaneProductFileDescriptorMaterialization,
        expectedAvailability: BridgeProductFileDescriptorAvailability
    ) {
        #expect(materialization.body == nil)
        #expect(materialization.payload.availability == expectedAvailability)
        #expect(materialization.payload.encoding == nil)
        #expect(!materialization.payload.endsMidLine)
        #expect(!materialization.payload.endsWithNewline)
        #expect(materialization.payload.payloadByteCount == 0)
        #expect(materialization.payload.payloadLineCount == 0)
        #expect(materialization.payload.totalLineCount == nil)
        #expect(materialization.payload.truncationKind == .complete)
        #expect(materialization.payload.virtualizedExtentKind == .unavailable)
    }

    private func loadCorpus() throws -> BridgeFilePrefixCorpus {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let data = try Data(contentsOf: projectRoot.appending(path: Self.corpusRelativePath))
        let vocabulary = BridgeProductStrictJSONMemberVocabulary(
            Set([
                "cases", "count", "didReachEnd", "endsMidLine", "endsWithNewline",
                "expectedReader", "isBinary", "isValidUTF8", "kind", "maximumPayloadBytes",
                "maximumPayloadLines", "name", "payloadByteCount", "payloadLineCount",
                "payloadSha256", "productAvailability", "schemaVersion", "sourceSegments",
                "truncationKind", "value",
            ])
        )
        return try BridgeProductStrictJSON.decode(
            BridgeFilePrefixCorpus.self,
            from: data,
            memberVocabulary: vocabulary
        )
    }

    private func readPrefix(_ source: Data, caseName: String) throws -> BridgeProductFilePrefix {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-file-prefix-corpus-\(caseName)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appending(path: "fixture.bin")
        try source.write(to: fileURL)
        return try BridgeProductFilePrefixReader.read(fileURL)
    }

    private func materialize(
        _ sourceData: Data,
        caseName: String
    ) async throws -> BridgePaneProductFileDescriptorMaterialization {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-file-materialization-\(caseName)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let relativePath = "fixture.bin"
        try sourceData.write(to: directoryURL.appending(path: relativePath))
        return try await BridgePaneProductFileContentSource.materialize(
            .init(
                relativePath: relativePath,
                rootURL: directoryURL,
                row: BridgeWorktreeTreeRowMetadata(
                    rowId: "row-1",
                    path: relativePath,
                    name: relativePath,
                    parentPath: nil,
                    depth: 0,
                    isDirectory: false,
                    fileId: nil,
                    sizeBytes: sourceData.count,
                    lineCount: nil,
                    changeStatus: nil
                ),
                source: try .init(
                    repoId: "00000000-0000-4000-8000-000000000001",
                    rootRevisionToken: "root-revision-1",
                    sourceCursor: "source-cursor-1",
                    sourceId: "file-source-1",
                    subscriptionGeneration: 1,
                    worktreeId: "00000000-0000-4000-8000-000000000002"
                )
            )
        )
    }
}

private struct BridgeFilePrefixCorpus: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cases
        case maximumPayloadBytes
        case maximumPayloadLines
        case schemaVersion
    }

    let cases: [BridgeFilePrefixCorpusCase]
    let maximumPayloadBytes: Int
    let maximumPayloadLines: Int
    let schemaVersion: Int

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowedKeys: CodingKeys.allCases, contract: "corpus")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cases = try container.decode([BridgeFilePrefixCorpusCase].self, forKey: .cases)
        maximumPayloadBytes = try container.decode(Int.self, forKey: .maximumPayloadBytes)
        maximumPayloadLines = try container.decode(Int.self, forKey: .maximumPayloadLines)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1, !cases.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported or empty Bridge File prefix corpus"
            )
        }
    }
}

private struct BridgeFilePrefixCorpusCase: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectedReader
        case name
        case productAvailability
        case sourceSegments
    }

    let expectedReader: BridgeFilePrefixExpectedReader
    let name: String
    let productAvailability: BridgeFilePrefixProductAvailability
    let sourceSegments: [BridgeFilePrefixSourceSegment]

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowedKeys: CodingKeys.allCases, contract: "case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expectedReader = try container.decode(BridgeFilePrefixExpectedReader.self, forKey: .expectedReader)
        name = try container.decode(String.self, forKey: .name)
        productAvailability = try container.decode(
            BridgeFilePrefixProductAvailability.self,
            forKey: .productAvailability
        )
        sourceSegments = try container.decode(
            [BridgeFilePrefixSourceSegment].self,
            forKey: .sourceSegments
        )
        guard !name.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Bridge File prefix case name cannot be empty"
            )
        }
        try validateAvailability(codingPath: decoder.codingPath)
    }

    func sourceData() throws -> Data {
        var source = Data()
        for segment in sourceSegments {
            source.append(try segment.data())
        }
        return source
    }

    private func validateAvailability(codingPath: [any CodingKey]) throws {
        let isExpectedAvailable = productAvailability == .available
        guard isExpectedAvailable == (expectedReader.payloadSHA256 != nil),
            productAvailability != .binary || expectedReader.isBinary,
            productAvailability != .unsupportedEncoding || !expectedReader.isValidUTF8
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription: "Bridge File product availability contradicts reader facts"
                )
            )
        }
    }
}

private struct BridgeFilePrefixExpectedReader: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case didReachEnd
        case endsMidLine
        case endsWithNewline
        case isBinary
        case isValidUTF8
        case payloadByteCount
        case payloadLineCount
        case payloadSha256
        case truncationKind
    }

    let didReachEnd: Bool
    let endsMidLine: Bool
    let endsWithNewline: Bool
    let isBinary: Bool
    let isValidUTF8: Bool
    let payloadByteCount: Int
    let payloadLineCount: Int
    let payloadSHA256: String?
    let truncationKind: BridgeProductFileTruncationKind

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowedKeys: CodingKeys.allCases, contract: "reader facts")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        didReachEnd = try container.decode(Bool.self, forKey: .didReachEnd)
        endsMidLine = try container.decode(Bool.self, forKey: .endsMidLine)
        endsWithNewline = try container.decode(Bool.self, forKey: .endsWithNewline)
        isBinary = try container.decode(Bool.self, forKey: .isBinary)
        isValidUTF8 = try container.decode(Bool.self, forKey: .isValidUTF8)
        payloadByteCount = try container.decode(Int.self, forKey: .payloadByteCount)
        payloadLineCount = try container.decode(Int.self, forKey: .payloadLineCount)
        payloadSHA256 = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .payloadSha256,
            from: container,
            codingPath: decoder.codingPath
        )
        truncationKind = try container.decode(
            BridgeProductFileTruncationKind.self,
            forKey: .truncationKind
        )
        guard payloadByteCount >= 0,
            payloadLineCount >= 0,
            !(endsMidLine && endsWithNewline),
            payloadSHA256.map({ $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil })
                ?? true
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid Bridge File prefix reader facts"
                )
            )
        }
    }
}

private enum BridgeFilePrefixProductAvailability: String, Decodable {
    case available
    case binary
    case unsupportedEncoding = "unsupported_encoding"
}

private enum BridgeFilePrefixSourceSegment: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case count
        case kind
        case value
    }

    case hex(Data)
    case repeatHex(pattern: Data, count: Int)
    case utf8(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "hex":
            try rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.kind, .value],
                contract: "hex segment"
            )
            self = .hex(try Self.decodeHex(container, forKey: .value))
        case "repeatHex":
            try rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.count, .kind, .value],
                contract: "repeat segment"
            )
            let count = try container.decode(Int.self, forKey: .count)
            guard count > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .count,
                    in: container,
                    debugDescription: "Repeat count must be positive"
                )
            }
            self = .repeatHex(pattern: try Self.decodeHex(container, forKey: .value), count: count)
        case "utf8":
            try rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.kind, .value],
                contract: "UTF-8 segment"
            )
            self = .utf8(try container.decode(String.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown Bridge File prefix segment kind"
            )
        }
    }

    func data() throws -> Data {
        switch self {
        case .hex(let data):
            return data
        case .repeatHex(let pattern, let count):
            guard let firstByte = pattern.first else { return Data() }
            if pattern.count == 1 {
                return Data(repeating: firstByte, count: count)
            }
            var data = Data(capacity: pattern.count * count)
            for _ in 0..<count { data.append(pattern) }
            return data
        case .utf8(let value):
            return Data(value.utf8)
        }
    }

    private static func decodeHex(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Data {
        let value = try container.decode(String.self, forKey: key)
        guard !value.isEmpty,
            value.count.isMultiple(of: 2),
            value.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil
        else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Hex segments require nonempty lowercase byte pairs"
            )
        }
        var data = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Invalid hexadecimal byte"
                )
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}

private func rejectUnknownKeys<Key: CodingKey>(
    from decoder: Decoder,
    allowedKeys: [Key],
    contract: String
) throws {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(allowedKeys.map(\.stringValue)),
        contract: "Bridge File prefix \(contract)"
    )
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
