import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Worktree creation command specs")
struct WorktreeCreationCommandSpecTests {
    @Test("New Worktree is the one command-bar root entry, targeted at a source worktree")
    func newWorktreeIsTheCommandBarEntry() {
        let definition = AppCommand.newWorktree.definition

        #expect(definition.label == "New Worktree...")
        #expect(definition.icon == .octicon(.gitWorktree))
        #expect(definition.helpText == "Create a worktree on a new branch from a worktree's HEAD, checked out clean")
        #expect(definition.surfacePolicy == .exposed([.commandBar]))
        #expect(definition.targeting == .targeted([.worktree]))
        #expect(definition.shortcut == nil)
        #expect(definition.commandBarGroupName == "Repo")
    }

    @Test("Fork Worktree is a distinct identity reached only through the Create row")
    func forkWorktreeIsNotPresentedAsASecondRoot() {
        let definition = AppCommand.forkWorktree.definition

        #expect(definition.label == "Fork Worktree...")
        #expect(definition.icon == .octicon(.repoClone))
        #expect(definition.helpText == "Fork a worktree with its uncommitted, untracked, and ignored files")
        #expect(definition.surfacePolicy == .notPresented)
        #expect(definition.targeting == .targeted([.worktree]))
        #expect(definition.shortcut == nil)
    }

    @Test("both creation commands are unexposed over typed IPC until a parameterized contract exists")
    func creationCommandsAreUnexposedOverIPC() {
        for command in [AppCommand.newWorktree, .forkWorktree] {
            let ipcSpec = command.ipcSpec
            #expect(ipcSpec.exposure == .debugTesting)
            #expect(ipcSpec.argumentVariants == [.noArguments])
            #expect(ipcSpec.allowedTargetKinds.isEmpty)
            #expect(ipcSpec.resultVariants == [.unavailable])
        }
    }

    @Test("creation kinds round-trip through their AppCommand identities")
    func creationKindsMapToCommands() {
        #expect(WorktreeCreationKind(command: .newWorktree) == .cleanCheckout)
        #expect(WorktreeCreationKind(command: .forkWorktree) == .fork)
        #expect(WorktreeCreationKind(command: .openWorktree) == nil)
        #expect(WorktreeCreationKind.cleanCheckout.command == .newWorktree)
        #expect(WorktreeCreationKind.fork.command == .forkWorktree)
    }
}
