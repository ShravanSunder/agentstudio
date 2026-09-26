import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("Worktree creation command specs")
struct WorktreeCreationCommandSpecTests {
    @Test("New Worktree is the one command-bar root entry, targeted at a repository")
    func newWorktreeIsTheCommandBarEntry() {
        let definition = AppCommand.newWorktree.definition

        #expect(definition.label == "New Worktree")
        #expect(definition.icon == .octicon(.gitWorktree))
        #expect(definition.helpText == "Choose a repository and create a new worktree")
        #expect(definition.surfacePolicy == .exposed([.commandBar]))
        #expect(definition.targeting == .contextualAndTargeted([.repo], preferredInvocation: .targetSelection))
        #expect(definition.shortcut == nil)
        #expect(definition.commandBarGroupName == "Repo")
    }

    @Test("From Default and Fork are distinct submenu identities")
    func forkWorktreeIsNotPresentedAsASecondRoot() {
        let defaultDefinition = AppCommand.newWorktreeFromDefault.definition
        let definition = AppCommand.forkWorktree.definition

        #expect(defaultDefinition.label == "From Default")
        #expect(defaultDefinition.targeting == .targeted([.repo]))
        #expect(defaultDefinition.surfacePolicy == .notPresented)
        #expect(definition.label == "Fork…")
        #expect(definition.icon == .octicon(.repoClone))
        #expect(definition.helpText == "Fork a worktree with its uncommitted, untracked, and ignored files")
        #expect(definition.surfacePolicy == .notPresented)
        #expect(definition.targeting == .targeted([.worktree]))
        #expect(definition.shortcut == nil)
    }

    @Test("both creation commands are unexposed over typed IPC until a parameterized contract exists")
    func creationCommandsAreUnexposedOverIPC() {
        for command in [AppCommand.newWorktree, .newWorktreeFromDefault, .forkWorktree] {
            let ipcSpec = command.ipcSpec
            #expect(ipcSpec.exposure == .debugTesting)
            #expect(ipcSpec.argumentVariants == [.noArguments])
            #expect(ipcSpec.allowedTargetKinds.isEmpty)
            #expect(ipcSpec.resultVariants == [.unavailable])
        }
    }

    @Test("creation kinds round-trip through their AppCommand identities")
    func creationKindsMapToCommands() {
        #expect(WorktreeCreationKind(command: .newWorktree) == nil)
        #expect(WorktreeCreationKind(command: .newWorktreeFromDefault) == .fromDefault)
        #expect(WorktreeCreationKind(command: .forkWorktree) == .fork)
        #expect(WorktreeCreationKind(command: .openWorktree) == nil)
        #expect(WorktreeCreationKind.fromDefault.command == .newWorktreeFromDefault)
        #expect(WorktreeCreationKind.fork.command == .forkWorktree)
    }
}
