import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("Bridge receiver navigation command contracts")
struct BridgeReceiverNavigationCommandContractTests {
    private static let documentCommands: [AppCommand] = [.activateBridgeFile, .closeBridgeFile]
    private static let worktreeCommands: [AppCommand] = [
        .activateBridgeReview, .addBridgeWorktree, .selectBridgeWorktree, .removeBridgeWorktree,
    ]

    @Test("every receiver command is a debug-channel headless layout command addressed by pane")
    func ipcClassification() {
        for command in Self.documentCommands + Self.worktreeCommands {
            let spec = command.ipcSpec
            #expect(spec.exposure == .debugTesting, "\(command.rawValue)")
            #expect(spec.executionMode == .headless, "\(command.rawValue)")
            #expect(spec.requiredPrivilege == .layoutMutate, "\(command.rawValue)")
            #expect(spec.allowedTargetKinds == [.window, .pane], "\(command.rawValue)")
            #expect(spec.resultVariants == [.applied, .unavailable], "\(command.rawValue)")
        }
    }

    @Test("documents are named by an absolute path; worktrees reuse the worktree-in-pane shape")
    func ipcArguments() {
        for command in Self.documentCommands {
            #expect(command.ipcSpec.argumentVariants == [.bridgeDocumentInPane], "\(command.rawValue)")
        }
        for command in Self.worktreeCommands {
            #expect(command.ipcSpec.argumentVariants == [.worktreeInPane], "\(command.rawValue)")
        }
    }

    @Test("B1 receiver commands add no command-bar rows (R7); membership commands still target a worktree")
    func interactivePresentation() {
        for command in [AppCommand.addBridgeWorktree, .selectBridgeWorktree, .removeBridgeWorktree] {
            let definition = AppCommandDispatcher.shared.definition(for: command)
            #expect(definition.surfacePolicy == .notPresented, "\(command.rawValue)")
            #expect(definition.targeting == .targeted([.worktree]), "\(command.rawValue)")
            #expect(definition.shortcut == nil, "\(command.rawValue)")
        }
        for command in Self.documentCommands + [.activateBridgeReview] {
            #expect(AppCommandDispatcher.shared.definition(for: command).surfacePolicy == .notPresented)
        }
    }
}
