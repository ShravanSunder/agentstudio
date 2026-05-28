import Foundation

enum WorkspaceBootStep: String, CaseIterable, Sendable {
    case loadCanonicalStore
    case loadCacheStore
    case loadUIStore
    case establishRuntimeBus
    case startFilesystemActor
    case startGitProjector
    case startForgeActor
    case startCacheCoordinator
    case triggerInitialTopologySync
    case armPersistenceObservation
    case readyForReactiveSidebar

    var purpose: String {
        switch self {
        case .loadCanonicalStore:
            return "Restore the durable workspace graph before any derived or runtime work reads it."
        case .loadCacheStore:
            return "Load rebuildable repo and sidebar cache without arming autosave during restore."
        case .loadUIStore:
            return "Load UI and inbox state before views bind to atom-backed presentation state."
        case .establishRuntimeBus:
            return "Create runtime, pane coordination, command routing, and event consumers."
        case .startFilesystemActor:
            return "Start filesystem discovery after the canonical workspace model exists."
        case .startGitProjector:
            return "Start git enrichment after filesystem discovery has a bus and scope."
        case .startForgeActor:
            return "Start forge enrichment after repo/worktree facts can be accumulated."
        case .startCacheCoordinator:
            return "Begin consuming runtime facts into canonical stores and rebuildable cache."
        case .triggerInitialTopologySync:
            return "Replay persisted topology into the runtime pipeline before reactive UI is declared ready."
        case .armPersistenceObservation:
            return "Arm debounced autosave after restore/replay boot mutations have settled."
        case .readyForReactiveSidebar:
            return "Mark the workspace graph ready for reactive sidebar and window presentation."
        }
    }
}

enum WorkspaceBootSequence {
    static let orderedSteps: [WorkspaceBootStep] = [
        .loadCanonicalStore,
        .loadCacheStore,
        .loadUIStore,
        .establishRuntimeBus,
        .startFilesystemActor,
        .startGitProjector,
        .startForgeActor,
        .startCacheCoordinator,
        .triggerInitialTopologySync,
        .armPersistenceObservation,
        .readyForReactiveSidebar,
    ]

    @MainActor
    static func run(_ perform: (WorkspaceBootStep) -> Void) {
        for step in orderedSteps {
            perform(step)
        }
    }
}
