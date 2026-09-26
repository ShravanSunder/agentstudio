import Foundation

enum BridgeProductFileBatchRowKind: String, Codable, Equatable, Sendable {
    case file
    case directory
    case deleted
}

/// The batch part's key is the canonical absolute document location. These
/// fields describe its current position and read capability, which may change
/// without changing that key.
struct BridgeProductFileBatchRow: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case changeStatus
        case displayKey
        case fileClass
        case kind
        case lineCount
        case oldPath
        case parentDisplayKey
        case readDescriptor
        case sizeBytes
        case sortKey
    }

    let changeStatus: BridgeProductFileChangeStatus?
    let displayKey: String
    let fileClass: BridgeFileClass?
    let kind: BridgeProductFileBatchRowKind
    let lineCount: Int?
    let oldPath: String?
    let parentDisplayKey: String?
    let readDescriptor: BridgeProductFileContentDescriptor?
    let sizeBytes: Int?
    let sortKey: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File batch row"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        changeStatus = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductFileChangeStatus.self,
            forKey: .changeStatus,
            from: container,
            codingPath: decoder.codingPath
        )
        displayKey = try container.decode(String.self, forKey: .displayKey)
        fileClass = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeFileClass.self,
            forKey: .fileClass,
            from: container,
            codingPath: decoder.codingPath
        )
        kind = try container.decode(BridgeProductFileBatchRowKind.self, forKey: .kind)
        lineCount = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .lineCount,
            from: container,
            codingPath: decoder.codingPath
        )
        oldPath = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .oldPath,
            from: container,
            codingPath: decoder.codingPath
        )
        parentDisplayKey = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .parentDisplayKey,
            from: container,
            codingPath: decoder.codingPath
        )
        readDescriptor = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductFileContentDescriptor.self,
            forKey: .readDescriptor,
            from: container,
            codingPath: decoder.codingPath
        )
        sizeBytes = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .sizeBytes,
            from: container,
            codingPath: decoder.codingPath
        )
        sortKey = try container.decode(String.self, forKey: .sortKey)
        try BridgeProductContractDecoding.validateDisplayPath(displayKey, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateDisplayPath(sortKey, codingPath: decoder.codingPath)
        if let oldPath {
            try BridgeProductContractDecoding.validateDisplayPath(oldPath, codingPath: decoder.codingPath)
        }
        if let parentDisplayKey {
            try BridgeProductContractDecoding.validateDisplayPath(parentDisplayKey, codingPath: decoder.codingPath)
        }
        if let lineCount {
            try BridgeProductContractDecoding.validateNonnegative(
                lineCount, name: "lineCount", codingPath: decoder.codingPath
            )
        }
        if let sizeBytes {
            try BridgeProductContractDecoding.validateNonnegative(
                sizeBytes, name: "sizeBytes", codingPath: decoder.codingPath
            )
        }
        if kind == .file {
            guard let fileClass, fileClass != .binary else {
                throw BridgeProductContractDecoding.invalidValue(
                    "File rows require a nonbinary file class",
                    codingPath: decoder.codingPath
                )
            }
        } else {
            guard fileClass == nil, sizeBytes == nil, lineCount == nil else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Directory and ghost rows cannot carry file extent facts",
                    codingPath: decoder.codingPath
                )
            }
        }
        guard kind == .file || readDescriptor == nil else {
            throw BridgeProductContractDecoding.invalidValue(
                "A directory or deleted File row cannot be opened",
                codingPath: decoder.codingPath
            )
        }
        guard kind != .deleted || changeStatus == .deleted || changeStatus == .renamed else {
            throw BridgeProductContractDecoding.invalidValue(
                "A deleted File row requires deleted or renamed status",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changeStatus, forKey: .changeStatus)
        try container.encode(displayKey, forKey: .displayKey)
        try container.encode(fileClass, forKey: .fileClass)
        try container.encode(kind, forKey: .kind)
        try container.encode(lineCount, forKey: .lineCount)
        try container.encode(oldPath, forKey: .oldPath)
        try container.encode(parentDisplayKey, forKey: .parentDisplayKey)
        try container.encode(readDescriptor, forKey: .readDescriptor)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(sortKey, forKey: .sortKey)
    }
}
