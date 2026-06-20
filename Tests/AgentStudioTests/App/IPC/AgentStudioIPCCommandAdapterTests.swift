import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC command adapter")
struct AgentStudioIPCCommandAdapterTests {
    @Test("lists app command specs through IPC command contracts")
    func listsAppCommandSpecsThroughIPCCommandContracts() throws {
        let harness = CommandAdapterHarness()

        let result = try harness.adapter.listCommands()
        let commandsById = Dictionary(uniqueKeysWithValues: result.commands.map { ($0.id, $0) })

        #expect(result.commands.count == AppCommand.allCases.count)

        let commandBar = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.showCommandBarEverything.rawValue)])
        #expect(commandBar.title == AppCommand.showCommandBarEverything.definition.label)
        #expect(commandBar.executionModes == [.uiPresentation])
        #expect(commandBar.targetKinds.isEmpty)
        #expect(commandBar.requiredPrivileges == [.uiPresent])

        let closePane = try #require(commandsById[IPCCommandIdentifier(rawValue: AppCommand.closePane.rawValue)])
        #expect(closePane.title == AppCommand.closePane.definition.label)
        #expect(closePane.executionModes == [.requiresInteractiveInput])
        #expect(closePane.targetKinds == [.pane])
        #expect(closePane.requiredPrivileges == [.layoutMutate])

        let copyCurrentPanePath = try #require(
            commandsById[IPCCommandIdentifier(rawValue: AppCommand.copyCurrentPanePath.rawValue)])
        #expect(copyCurrentPanePath.executionModes == [.requiresInteractiveInput])
        #expect(copyCurrentPanePath.targetKinds == [.pane])
        #expect(copyCurrentPanePath.requiredPrivileges == [.workspaceRead])
    }

    @Test("command list entries are full-catalog IPC projections")
    func commandListEntriesAreFullCatalogIPCProjections() throws {
        let harness = CommandAdapterHarness()

        let result = try harness.adapter.listCommands()
        let commandsById = Dictionary(uniqueKeysWithValues: result.commands.map { ($0.id, $0) })

        for command in AppCommand.allCases {
            let definition = command.definition
            let entry = try #require(commandsById[IPCCommandIdentifier(rawValue: command.rawValue)])

            #expect(entry == definition.ipcCommandListEntry)
            #expect(entry.title == definition.label)
        }
    }

    @Test("public IPC command contracts do not expose tooltip vocabulary")
    func publicIPCCommandContractsDoNotExposeTooltipVocabulary() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("ControlTooltip"))
        #expect(!source.contains("tooltip"))
        #expect(!source.contains("toolTip"))
    }

    @Test("encoded command list entries expose only IPC contract keys")
    func encodedCommandListEntriesExposeOnlyIPCContractKeys() throws {
        let harness = CommandAdapterHarness()
        let result = try harness.adapter.listCommands()
        let encodedData = try JSONEncoder().encode(result)
        let decodedObject = try #require(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        let encodedCommands = try #require(decodedObject["commands"] as? [[String: Any]])
        let expectedEntryKeys = Set([
            "id",
            "title",
            "executionModes",
            "targetKinds",
            "requiredPrivileges",
        ])

        #expect(!encodedCommands.isEmpty)
        for encodedCommand in encodedCommands {
            #expect(Set(encodedCommand.keys) == expectedEntryKeys)
        }
    }

    @Test("rejects ui-presentation command specs before workspace window checks")
    func rejectsUIPresentationCommandSpecsBeforeWorkspaceWindowChecks() throws {
        let harness = CommandAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.showCommandBarEverything.rawValue),
                    targetHandle: nil
                )
            )
            Issue.record("command bar command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresPresentation)
        }
    }

    @Test("rejects command bar specs because they require explicit UI presentation")
    func rejectsCommandBarSpecsBecauseTheyRequireExplicitUIPresentation() throws {
        let windowId = UUID()
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(windowId)
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.showCommandBarEverything.rawValue),
                    targetHandle: nil
                )
            )
            Issue.record("command bar command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresPresentation)
        }
    }

    @Test("rejects interactive command specs without misclassifying them as UI presentation")
    func rejectsInteractiveCommandSpecsWithoutMisclassifyingThemAsUIPresentation() throws {
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID())
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: AppCommand.copyCurrentPanePath.rawValue),
                    targetHandle: nil
                )
            )
            Issue.record("interactive command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresParameters)
        }
    }

    @Test("unknown command ids return unsupported command after decoding")
    func unknownCommandIdsReturnUnsupportedCommandAfterDecoding() throws {
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID())
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(commandId: IPCCommandIdentifier(rawValue: "futureCommand"), targetHandle: nil)
            )
            Issue.record("unknown command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .unsupportedCommand)
        }
    }

    @Test("target handles are rejected without adding command execute target semantics")
    func targetHandlesAreRejectedWithoutAddingCommandExecuteTargetSemantics() throws {
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID())
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(
                    commandId: IPCCommandIdentifier(rawValue: "futureCommand"), targetHandle: "pane:1")
            )
            Issue.record("targeted command.execute unexpectedly added target semantics")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .targetNotFound)
        }
    }
}

@MainActor
private struct CommandAdapterHarness {
    let adapter: AgentStudioIPCCommandAdapter

    init(
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID())
    ) {
        adapter = AgentStudioIPCCommandAdapter(
            windowLifecycleReader: FakeCommandWorkspaceWindowLifecycleReader(snapshot: windowSnapshot)
        )
    }
}

private struct FakeCommandWorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading {
    let snapshotValue: WorkspaceWindowLifecycleSnapshot

    init(snapshot: WorkspaceWindowLifecycleSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> WorkspaceWindowLifecycleSnapshot {
        snapshotValue
    }
}

extension WorkspaceWindowLifecycleSnapshot {
    fileprivate static var empty: Self {
        Self(
            registeredWindowIds: [],
            keyWindowId: nil,
            focusedWindowId: nil,
            preferredWorkspaceWindowId: nil
        )
    }

    fileprivate static func singleActiveWindow(_ windowId: UUID) -> Self {
        Self(
            registeredWindowIds: [windowId],
            keyWindowId: windowId,
            focusedWindowId: windowId,
            preferredWorkspaceWindowId: windowId
        )
    }
}
