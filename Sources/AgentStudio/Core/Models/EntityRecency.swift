import Foundation

enum EntityRecencyInteraction: String, Hashable, Sendable {
    case opened
    case focused
}

enum ApplicationRecentEntity: Hashable, Sendable {
    case repository(repositoryStableKey: String)
    case worktree(worktreeStableKey: String)

    var storageKind: String {
        switch self {
        case .repository:
            "repository"
        case .worktree:
            "worktree"
        }
    }

    var storageKey: String {
        switch self {
        case .repository(let repositoryStableKey):
            repositoryStableKey
        case .worktree(let worktreeStableKey):
            worktreeStableKey
        }
    }

    init(storageKind: String, storageKey: String) throws {
        try EntityRecencyValidation.validateStableKey(storageKey)
        switch storageKind {
        case "repository":
            self = .repository(repositoryStableKey: storageKey)
        case "worktree":
            self = .worktree(worktreeStableKey: storageKey)
        default:
            throw EntityRecencyValidationError.unsupportedEntityKind
        }
    }
}

enum WorkspaceRecentEntity: Hashable, Sendable {
    case pane(paneID: UUID)

    var storageKind: String {
        "pane"
    }

    var storageKey: String {
        switch self {
        case .pane(let paneID):
            paneID.uuidString
        }
    }

    init(storageKind: String, storageKey: String) throws {
        guard storageKind == "pane" else {
            throw EntityRecencyValidationError.unsupportedEntityKind
        }
        guard
            let paneID = UUID(uuidString: storageKey),
            paneID.uuidString == storageKey
        else {
            throw EntityRecencyValidationError.invalidEntityKey
        }
        self = .pane(paneID: paneID)
    }
}

enum EntityRecencyValidationError: Error, Equatable {
    case invalidStableKey
    case invalidEntityKey
    case invalidTimestamp
    case unsupportedEntityKind
    case unsupportedInteraction
}

struct ApplicationEntityRecency: Hashable, Sendable {
    let entity: ApplicationRecentEntity
    let interaction: EntityRecencyInteraction
    let lastInteractedAt: Date

    init(
        entity: ApplicationRecentEntity,
        interaction: EntityRecencyInteraction,
        lastInteractedAt: Date
    ) throws {
        try EntityRecencyValidation.validateStableKey(entity.storageKey)
        guard interaction == .opened else {
            throw EntityRecencyValidationError.unsupportedInteraction
        }
        try EntityRecencyValidation.validateTimestamp(lastInteractedAt)
        self.entity = entity
        self.interaction = interaction
        self.lastInteractedAt = lastInteractedAt
    }
}

struct WorkspaceEntityRecency: Hashable, Sendable {
    let workspaceID: UUID
    let entity: WorkspaceRecentEntity
    let interaction: EntityRecencyInteraction
    let lastInteractedAt: Date

    init(
        workspaceID: UUID,
        entity: WorkspaceRecentEntity,
        interaction: EntityRecencyInteraction,
        lastInteractedAt: Date
    ) throws {
        guard interaction == .focused else {
            throw EntityRecencyValidationError.unsupportedInteraction
        }
        try EntityRecencyValidation.validateTimestamp(lastInteractedAt)
        self.workspaceID = workspaceID
        self.entity = entity
        self.interaction = interaction
        self.lastInteractedAt = lastInteractedAt
    }
}

private enum EntityRecencyValidation {
    static func validateStableKey(_ stableKey: String) throws {
        guard
            stableKey.count == 16,
            stableKey.utf8.allSatisfy({
                ($0 >= Character("0").asciiValue! && $0 <= Character("9").asciiValue!)
                    || ($0 >= Character("a").asciiValue! && $0 <= Character("f").asciiValue!)
            })
        else {
            throw EntityRecencyValidationError.invalidStableKey
        }
    }

    static func validateTimestamp(_ timestamp: Date) throws {
        guard timestamp.timeIntervalSince1970.isFinite else {
            throw EntityRecencyValidationError.invalidTimestamp
        }
    }
}
