import Foundation

enum BridgeProductFileChangeStatus: String, Codable, Equatable, Sendable {
    case added
    case deleted
    case modified
    case renamed
    case copied
    case typeChanged
    case unmerged
    case untracked
}

enum BridgeProductFileMetadataLoadedBy: String, Codable, Equatable, Sendable {
    case startupWindow = "startup_window"
    case foreground
    case visible
    case nearby
    case speculative
    case idle
    case delta
    case reset
    case replacement
}

struct BridgeProductFileMetadataLineage: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lane
        case loadedBy
    }

    let lane: BridgeProductDemandLane
    let loadedBy: BridgeProductFileMetadataLoadedBy

    init(lane: BridgeProductDemandLane, loadedBy: BridgeProductFileMetadataLoadedBy) {
        self.lane = lane
        self.loadedBy = loadedBy
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File metadata lineage"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lane = try container.decode(BridgeProductDemandLane.self, forKey: .lane)
        self.loadedBy = try container.decode(BridgeProductFileMetadataLoadedBy.self, forKey: .loadedBy)
    }
}

struct BridgeProductFileTreeRow: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case changeStatus
        case depth
        case fileId
        case isDirectory
        case lineCount
        case name
        case parentPath
        case path
        case rowId
        case sizeBytes
    }

    let changeStatus: BridgeProductFileChangeStatus?
    let depth: Int
    let fileId: String?
    let isDirectory: Bool
    let lineCount: Int?
    let name: String
    let parentPath: String?
    let path: String
    let rowId: String
    let sizeBytes: Int?

    init(
        changeStatus: BridgeProductFileChangeStatus?,
        depth: Int,
        fileId: String?,
        isDirectory: Bool,
        lineCount: Int?,
        name: String,
        parentPath: String?,
        path: String,
        rowId: String,
        sizeBytes: Int?
    ) throws {
        self.changeStatus = changeStatus
        self.depth = depth
        self.fileId = fileId
        self.isDirectory = isDirectory
        self.lineCount = lineCount
        self.name = name
        self.parentPath = parentPath
        self.path = path
        self.rowId = rowId
        self.sizeBytes = sizeBytes
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File metadata tree row"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.changeStatus = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductFileChangeStatus.self,
            forKey: .changeStatus,
            from: container,
            codingPath: decoder.codingPath
        )
        self.depth = try container.decode(Int.self, forKey: .depth)
        self.fileId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .fileId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        self.lineCount = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .lineCount,
            from: container,
            codingPath: decoder.codingPath
        )
        self.name = try container.decode(String.self, forKey: .name)
        self.parentPath = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .parentPath,
            from: container,
            codingPath: decoder.codingPath
        )
        self.path = try container.decode(String.self, forKey: .path)
        self.rowId = try container.decode(String.self, forKey: .rowId)
        self.sizeBytes = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .sizeBytes,
            from: container,
            codingPath: decoder.codingPath
        )
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try validate(codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changeStatus, forKey: .changeStatus)
        try container.encode(depth, forKey: .depth)
        try container.encode(fileId, forKey: .fileId)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(lineCount, forKey: .lineCount)
        try container.encode(name, forKey: .name)
        try container.encode(parentPath, forKey: .parentPath)
        try container.encode(path, forKey: .path)
        try container.encode(rowId, forKey: .rowId)
        try container.encode(sizeBytes, forKey: .sizeBytes)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateNonnegative(depth, name: "depth", codingPath: codingPath)
        if let fileId {
            try BridgeProductContractDecoding.validateIdentifier(fileId, codingPath: codingPath)
        }
        if let lineCount {
            try BridgeProductContractDecoding.validateNonnegative(
                lineCount,
                name: "lineCount",
                codingPath: codingPath
            )
        }
        try BridgeProductContractDecoding.validateDisplayPath(name, codingPath: codingPath)
        if let parentPath {
            try BridgeProductContractDecoding.validateDisplayPath(parentPath, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(rowId, codingPath: codingPath)
        if let sizeBytes {
            try BridgeProductContractDecoding.validateNonnegative(
                sizeBytes,
                name: "sizeBytes",
                codingPath: codingPath
            )
        }
    }
}

enum BridgeProductFileTreeOperation: Codable, Equatable, Sendable {
    case upsertRows([BridgeProductFileTreeRow])
    case removeRows(paths: [String], rowIds: [String])

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case op
        case paths
        case rowIds
        case rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .op) {
        case "upsertRows":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.op, .rows])
            let rows = try container.decode([BridgeProductFileTreeRow].self, forKey: .rows)
            try Self.validateMemberCount(rows.count, codingPath: decoder.codingPath)
            self = .upsertRows(rows)
        case "removeRows":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.op, .paths, .rowIds])
            let paths = try container.decode([String].self, forKey: .paths)
            let rowIds = try container.decode([String].self, forKey: .rowIds)
            guard !paths.isEmpty || !rowIds.isEmpty else {
                throw BridgeProductContractDecoding.invalidValue(
                    "File metadata row removal requires a row or path identity",
                    codingPath: decoder.codingPath
                )
            }
            try Self.validateMemberCount(paths.count, codingPath: decoder.codingPath)
            try Self.validateMemberCount(rowIds.count, codingPath: decoder.codingPath)
            for path in paths {
                try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
            }
            for rowId in rowIds {
                try BridgeProductContractDecoding.validateIdentifier(rowId, codingPath: decoder.codingPath)
            }
            self = .removeRows(paths: paths, rowIds: rowIds)
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File metadata tree operation",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try validate(codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsertRows(let rows):
            try container.encode("upsertRows", forKey: .op)
            try container.encode(rows, forKey: .rows)
        case .removeRows(let paths, let rowIds):
            try container.encode("removeRows", forKey: .op)
            try container.encode(paths, forKey: .paths)
            try container.encode(rowIds, forKey: .rowIds)
        }
    }

    var memberCount: Int {
        switch self {
        case .upsertRows(let rows): rows.count
        case .removeRows(let paths, let rowIds): max(paths.count, rowIds.count)
        }
    }

    private func validate(codingPath: [any CodingKey]) throws {
        switch self {
        case .upsertRows(let rows):
            try Self.validateMemberCount(rows.count, codingPath: codingPath)
        case .removeRows(let paths, let rowIds):
            guard !paths.isEmpty || !rowIds.isEmpty else {
                throw BridgeProductContractDecoding.invalidValue(
                    "File metadata row removal requires a row or path identity",
                    codingPath: codingPath
                )
            }
            try Self.validateMemberCount(paths.count, codingPath: codingPath)
            try Self.validateMemberCount(rowIds.count, codingPath: codingPath)
            for path in paths {
                try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
            }
            for rowId in rowIds {
                try BridgeProductContractDecoding.validateIdentifier(rowId, codingPath: codingPath)
            }
        }
    }

    private static func rejectUnknownKeys(from decoder: Decoder, allowedKeys: Set<CodingKeys>) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(allowedKeys.map(\.rawValue)),
            contract: "File metadata tree operation"
        )
    }

    private static func validateMemberCount(_ count: Int, codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateMaximum(
            count,
            maximum: BridgeProductWireContract.maximumFileMetadataDeltaMemberCount,
            name: "File metadata tree operation member count",
            codingPath: codingPath
        )
    }
}

struct BridgeProductFileStatusSummary: Equatable, Sendable {
    let ahead: Int?
    let behind: Int?
    let branchName: String?
    let staged: Int?
    let unstaged: Int?
    let untracked: Int?
}

enum BridgeProductFileStatusPatch: Codable, Equatable, Sendable {
    case summary(BridgeProductFileStatusSummary)
    case invalidated
    case path(path: String, status: BridgeProductFileChangeStatus?)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ahead
        case behind
        case branchName
        case patchKind
        case path
        case reason
        case staged
        case status
        case unstaged
        case untracked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .patchKind) {
        case "summary":
            try Self.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [.ahead, .behind, .branchName, .patchKind, .staged, .unstaged, .untracked]
            )
            let ahead = try Self.decodeCount(.ahead, from: container, codingPath: decoder.codingPath)
            let behind = try Self.decodeCount(.behind, from: container, codingPath: decoder.codingPath)
            let branchName = try BridgeProductContractDecoding.decodeRequiredNullable(
                String.self,
                forKey: .branchName,
                from: container,
                codingPath: decoder.codingPath
            )
            if let branchName {
                try BridgeProductContractDecoding.validateSafeMessage(
                    branchName,
                    codingPath: decoder.codingPath
                )
            }
            let staged = try Self.decodeCount(.staged, from: container, codingPath: decoder.codingPath)
            let unstaged = try Self.decodeCount(.unstaged, from: container, codingPath: decoder.codingPath)
            let untracked = try Self.decodeCount(.untracked, from: container, codingPath: decoder.codingPath)
            self = .summary(
                BridgeProductFileStatusSummary(
                    ahead: ahead,
                    behind: behind,
                    branchName: branchName,
                    staged: staged,
                    unstaged: unstaged,
                    untracked: untracked
                )
            )
        case "invalidated":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.patchKind, .reason])
            guard try container.decode(String.self, forKey: .reason) == "git_status_changed" else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Invalid File metadata status invalidation reason",
                    codingPath: decoder.codingPath
                )
            }
            self = .invalidated
        case "path":
            try Self.rejectUnknownKeys(from: decoder, allowedKeys: [.patchKind, .path, .status])
            let path = try container.decode(String.self, forKey: .path)
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: decoder.codingPath)
            self = .path(
                path: path,
                status: try BridgeProductContractDecoding.decodeRequiredNullable(
                    BridgeProductFileChangeStatus.self,
                    forKey: .status,
                    from: container,
                    codingPath: decoder.codingPath
                )
            )
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid File metadata status patch",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try validate(codingPath: encoder.codingPath)
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .summary(let summary):
            try container.encode(summary.ahead, forKey: .ahead)
            try container.encode(summary.behind, forKey: .behind)
            try container.encode(summary.branchName, forKey: .branchName)
            try container.encode("summary", forKey: .patchKind)
            try container.encode(summary.staged, forKey: .staged)
            try container.encode(summary.unstaged, forKey: .unstaged)
            try container.encode(summary.untracked, forKey: .untracked)
        case .invalidated:
            try container.encode("invalidated", forKey: .patchKind)
            try container.encode("git_status_changed", forKey: .reason)
        case .path(let path, let status):
            try container.encode("path", forKey: .patchKind)
            try container.encode(path, forKey: .path)
            try container.encode(status, forKey: .status)
        }
    }

    private static func decodeCount(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>,
        codingPath: [any CodingKey]
    ) throws -> Int? {
        let value = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: key,
            from: container,
            codingPath: codingPath
        )
        if let value {
            try BridgeProductContractDecoding.validateNonnegative(
                value,
                name: key.rawValue,
                codingPath: codingPath
            )
        }
        return value
    }

    private func validate(codingPath: [any CodingKey]) throws {
        switch self {
        case .summary(let summary):
            for (name, value) in [
                ("ahead", summary.ahead),
                ("behind", summary.behind),
                ("staged", summary.staged),
                ("unstaged", summary.unstaged),
                ("untracked", summary.untracked),
            ] {
                if let value {
                    try BridgeProductContractDecoding.validateNonnegative(
                        value,
                        name: name,
                        codingPath: codingPath
                    )
                }
            }
            if let branchName = summary.branchName {
                try BridgeProductContractDecoding.validateSafeMessage(
                    branchName,
                    codingPath: codingPath
                )
            }
        case .invalidated:
            break
        case .path(let path, _):
            try BridgeProductContractDecoding.validateDisplayPath(path, codingPath: codingPath)
        }
    }

    private static func rejectUnknownKeys(from decoder: Decoder, allowedKeys: Set<CodingKeys>) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(allowedKeys.map(\.rawValue)),
            contract: "File metadata status patch"
        )
    }
}

enum BridgeProductFileInvalidationReason: String, Codable, Equatable, Sendable {
    case filesystemEvent
    case gitStatusChanged
    case contentChanged
    case sourceReset
    case unknown
}
