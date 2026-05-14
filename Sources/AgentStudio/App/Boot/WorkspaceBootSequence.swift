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
    case readyForReactiveSidebar
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
        .readyForReactiveSidebar,
    ]

    @MainActor
    static func run(_ perform: (WorkspaceBootStep) -> Void) {
        for step in orderedSteps {
            perform(step)
        }
    }
}
