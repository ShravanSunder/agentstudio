import Foundation

struct CommandBarActivationGeneration: Equatable, Sendable {
    fileprivate let activationGeneration: Int
    fileprivate let rootSessionGeneration: Int
    fileprivate let workspaceID: UUID
}

struct CommandBarActivationGenerationGate {
    private var activationGeneration = 0

    mutating func begin(
        rootSessionGeneration: Int,
        workspaceID: UUID
    ) -> CommandBarActivationGeneration {
        activationGeneration += 1
        return CommandBarActivationGeneration(
            activationGeneration: activationGeneration,
            rootSessionGeneration: rootSessionGeneration,
            workspaceID: workspaceID
        )
    }

    func accepts(
        _ activation: CommandBarActivationGeneration,
        rootSessionGeneration: Int,
        workspaceID: UUID
    ) -> Bool {
        activation.activationGeneration == activationGeneration
            && activation.rootSessionGeneration == rootSessionGeneration
            && activation.workspaceID == workspaceID
    }

    mutating func invalidate() {
        activationGeneration += 1
    }
}
