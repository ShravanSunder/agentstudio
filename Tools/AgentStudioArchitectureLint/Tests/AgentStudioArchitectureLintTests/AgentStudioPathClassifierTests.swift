import Testing

@testable import AgentStudioArchitectureLintCore

@Suite("Agent Studio module ownership")
struct AgentStudioPathClassifierTests {
    @Test("Foundation and worktree-operation leaves sit at Infrastructure depth")
    func dependencyLeafModulesBelongToInfrastructureLayer() {
        #expect(AgentStudioPathClassifier.importedModuleOwner(["AgentStudioPrimitives"]) == .infrastructure)
        #expect(AgentStudioPathClassifier.importedModuleOwner(["AgentStudioWorktreeOperations"]) == .infrastructure)
    }
}
