import Foundation

enum WorkspaceIdentityPersistenceCapture: Sendable {
    case currentIdentity
}

enum WorkspaceWindowMemoryPersistenceCapture: Sendable {
    case currentWindowMemory
}

enum WorkspacePaneGraphPersistenceCaptureOperation: Equatable, Sendable {
    case insertion(UUID)
    case valueChange(UUID)
    case removal(UUID)
}

struct WorkspacePaneGraphPersistenceCapture: Equatable, Sendable {
    let operations: [WorkspacePaneGraphPersistenceCaptureOperation]
}

enum WorkspacePaneGraphPersistenceCaptureError: Error, Equatable {
    case duplicateOrConflictingPaneID(UUID)
    case emptyCapture
    case insertedPaneAlreadyExists(UUID)
    case existingPaneMissing(UUID)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

enum WorkspaceTabShellPersistenceCaptureOperation: Equatable, Sendable {
    case insertion(UUID)
    case valueChange(UUID)
    case removal(UUID)
}

struct WorkspaceTabShellPersistenceCapture: Equatable, Sendable {
    let operations: [WorkspaceTabShellPersistenceCaptureOperation]
}

enum WorkspaceTabGraphPersistenceCaptureOperation: Equatable, Sendable {
    case insertion(UUID)
    case valueChange(UUID)
    case removal(UUID)
}

struct WorkspaceTabGraphPersistenceCapture: Equatable, Sendable {
    let operations: [WorkspaceTabGraphPersistenceCaptureOperation]
}

enum WorkspaceDrawerCursorPersistenceCapture: Equatable, Sendable {
    case insertion(UUID)
    case removal(UUID)
    case replacement(removing: UUID, inserting: UUID)
}

enum WorkspaceDrawerCursorPersistenceCaptureError: Error, Equatable {
    case currentDrawerMismatch(expected: UUID?, actual: UUID?)
    case replacementUsesSameIdentity(UUID)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

enum WorkspaceTabCursorPersistenceCapture: Equatable, Sendable {
    case insertion
    case valueChange
    case removal
}

enum WorkspaceTabCursorPersistenceCaptureError: Error, Equatable {
    case activeTabAlreadyExists(UUID)
    case activeTabMissing
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}

enum WorkspaceActiveArrangementPersistenceCapture: Equatable, Sendable {
    case insertion(tabID: UUID)
    case valueChange(tabID: UUID)
    case removal(tabID: UUID)
}

enum WorkspaceActivePanePersistenceCapture: Equatable, Sendable {
    case insertion(arrangementID: UUID)
    case valueChange(arrangementID: UUID)
    case removal(arrangementID: UUID)
}

enum WorkspaceActiveDrawerChildPersistenceCapture: Equatable, Sendable {
    case insertion(ArrangementDrawerCursorKey)
    case valueChange(ArrangementDrawerCursorKey)
    case removal(ArrangementDrawerCursorKey)
}

struct WorkspaceArrangementCursorPersistenceCapture: Equatable, Sendable {
    let activeArrangements: [WorkspaceActiveArrangementPersistenceCapture]
    let activePanes: [WorkspaceActivePanePersistenceCapture]
    let activeDrawerChildren: [WorkspaceActiveDrawerChildPersistenceCapture]
}

enum WorkspaceArrangementCursorPersistenceCaptureError: Error, Equatable {
    case duplicateOrConflictingActiveArrangement(UUID)
    case duplicateOrConflictingActiveDrawerChild(ArrangementDrawerCursorKey)
    case duplicateOrConflictingActivePane(UUID)
    case emptyCapture
    case existingActiveArrangementMissing(UUID)
    case existingActiveDrawerChildMissing(ArrangementDrawerCursorKey)
    case existingActivePaneMissing(UUID)
    case insertedActiveArrangementAlreadyExists(UUID)
    case insertedActiveDrawerChildAlreadyExists(ArrangementDrawerCursorKey)
    case insertedActivePaneAlreadyExists(UUID)
    case snapshotPreparation(WorkspaceSnapshotPreparationRejection)
}
