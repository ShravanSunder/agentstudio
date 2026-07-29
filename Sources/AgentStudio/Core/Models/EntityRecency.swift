import Foundation

package enum EntityRecencyInteraction: String, Hashable, Sendable {
    case opened
    case focused
}

package enum ApplicationRecentEntity: Hashable, Sendable {
    case repository(repositoryStableKey: String)
    case worktree(worktreeStableKey: String)

    package var storageKind: String {
        switch self {
        case .repository:
            "repository"
        case .worktree:
            "worktree"
        }
    }

    package var storageKey: String {
        switch self {
        case .repository(let repositoryStableKey):
            repositoryStableKey
        case .worktree(let worktreeStableKey):
            worktreeStableKey
        }
    }

    package init(storageKind: String, storageKey: String) throws {
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

package enum WorkspaceRecentEntity: Hashable, Sendable {
    case pane(paneID: UUID)

    package var storageKind: String {
        "pane"
    }

    package var storageKey: String {
        switch self {
        case .pane(let paneID):
            paneID.uuidString
        }
    }

    package init(storageKind: String, storageKey: String) throws {
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

package enum EntityRecencyValidationError: Error, Equatable {
    case invalidStableKey
    case invalidEntityKey
    case invalidTimestamp
    case unsupportedEntityKind
    case unsupportedInteraction
}

package struct ApplicationEntityRecency: Hashable, Sendable {
    package let entity: ApplicationRecentEntity
    package let interaction: EntityRecencyInteraction
    package let lastInteractedAt: Date

    package init(
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

package struct WorkspaceEntityRecency: Hashable, Sendable {
    package let workspaceID: UUID
    package let entity: WorkspaceRecentEntity
    package let interaction: EntityRecencyInteraction
    package let lastInteractedAt: Date

    package init(
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
