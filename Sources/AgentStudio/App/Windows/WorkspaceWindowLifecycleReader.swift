import Foundation

struct WorkspaceWindowLifecycleSnapshot: Equatable, Sendable {
    let registeredWindowIds: [UUID]
    let keyWindowId: UUID?
    let focusedWindowId: UUID?
    let preferredWorkspaceWindowId: UUID?
}

@MainActor
protocol WorkspaceWindowLifecycleReading: Sendable {
    func snapshot() -> WorkspaceWindowLifecycleSnapshot
}

struct WorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading, @unchecked Sendable {
    private let lifecycleStore: WindowLifecycleAtom

    init(lifecycleStore: WindowLifecycleAtom) {
        self.lifecycleStore = lifecycleStore
    }

    func snapshot() -> WorkspaceWindowLifecycleSnapshot {
        WorkspaceWindowLifecycleSnapshot(
            registeredWindowIds: lifecycleStore.registeredWindowIds.sorted { lhs, rhs in
                lhs.uuidString < rhs.uuidString
            },
            keyWindowId: lifecycleStore.keyWindowId,
            focusedWindowId: lifecycleStore.focusedWindowId,
            preferredWorkspaceWindowId: lifecycleStore.preferredWorkspaceWindowId
        )
    }
}
