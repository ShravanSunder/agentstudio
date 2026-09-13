import AgentStudioProgrammaticControl
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("AgentStudio IPC command presentation isolation", .serialized)
struct AgentStudioIPCCommandPresentationIsolationTests {
    @Test("full public IPC command list sorted JSON remains byte equivalent")
    func fullPublicIPCCommandListSortedJSONRemainsByteEquivalent() throws {
        let adapter = makeIPCCommandAdapterForPresentationIsolationTests()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedCommandList = try encoder.encode(adapter.listCommands())
        let encodedCommandListSHA256 = SHA256.hash(data: encodedCommandList)
            .map { String(format: "%02x", $0) }
            .joined()

        // Accepted catalog includes Focus Sidebar, pinned navigation and the 90%/33% terminal commands.
        #expect(
            encodedCommandListSHA256
                == "197556569d3e3e612d45adfa39df8da104a8947e87171f55a658f57dcff69775"
        )
    }

    @Test("internal IPC policy uses discriminated exposure, durable-target, and argument contracts")
    func internalIPCPolicyUsesDiscriminatedExposureDurableTargetAndArgumentContracts() {
        #expect(
            AppCommand.closePane.ipcSpec.exposure
                == .interactive(
                    durableTarget: .required(primary: .pane, additional: []),
                    requiredPrivilege: .layoutMutate
                )
        )
        #expect(
            AppCommand.zoomPane.ipcSpec.exposure
                == .headless(
                    durableTarget: .required(primary: .pane, additional: []),
                    requiredPrivilege: .layoutMutate
                )
        )
        #expect(AppCommand.showInboxNotifications.ipcSpec.exposure == .notExposed)
        #expect(
            AppCommand.splitRight.ipcSpec.exposure
                == .interactive(
                    durableTarget: .required(primary: .tab, additional: [.pane]),
                    requiredPrivilege: .layoutMutate
                )
        )
        #expect(AppCommand.showCommandBarEverything.ipcSpec.exposure == .uiPresentation)
        #expect(AppCommand.focusSidebar.ipcSpec.exposure == .uiPresentation)
        for command in [AppCommand.focusPreviousPinnedPane, .focusNextPinnedPane] {
            #expect(
                command.ipcSpec.exposure
                    == .interactive(
                        durableTarget: .targetless, requiredPrivilege: .layoutMutate
                    ))
            #expect(command.ipcSpec.argumentContract == .noArguments)
        }
        #expect(AppCommand.showViewer.ipcSpec.exposure == .notExposed)
        #expect(
            AppCommand.scrollSmallStepDown.ipcSpec.exposure
                == .interactive(
                    durableTarget: .required(primary: .pane, additional: []),
                    requiredPrivilege: .terminalInputWrite
                )
        )

        #expect(AppCommand.closePane.ipcSpec.argumentContract == .noArguments)
        #expect(AppCommand.scrollPageDown.ipcSpec.argumentContract == .noArguments)
        #expect(AppCommand.setReposSortFieldName.ipcSpec.argumentContract == .noArguments)
        #expect(
            AppCommand.setInboxRowStateFilter.ipcSpec.argumentContract
                == .inboxRowStateFilter
        )
        #expect(
            AppCommand.setInboxContentMode.ipcSpec.argumentContract
                == .inboxContentMode
        )
    }

    @Test("execution requests use exhaustive argument payloads decoded from the IPC contract")
    func executionRequestsUseExhaustiveArgumentPayloadsDecodedFromIPCContract() throws {
        let defaultRequest = AppCommandExecutionRequest(command: .showReposSidebar)
        let noArguments = try AppCommandExecutionArguments.commandOwnedArguments(
            contract: .noArguments,
            rawArguments: [:],
            argumentsContainOnlyStrings: true
        )
        #expect(defaultRequest.arguments == .noArguments)
        #expect(noArguments == .noArguments)
    }

    // Mutation caught: the presentation-policy migration changes accepted public command metadata or encoding.
    @Test("representative public IPC metadata remains byte and value equivalent")
    func representativePublicIPCMetadataRemainsByteAndValueEquivalent() throws {
        let adapter = makeIPCCommandAdapterForPresentationIsolationTests()
        let result = try adapter.listCommands()
        let commandsById = Dictionary(uniqueKeysWithValues: result.commands.map { ($0.id, $0) })
        for obsoleteID in ["scrollQuarterPageUp", "scrollQuarterPageDown"] {
            #expect(commandsById[IPCCommandIdentifier(rawValue: obsoleteID)] == nil)
        }
        for (commandID, title) in [
            ("focusPreviousPinnedPane", "Previous Pinned Pane"),
            ("focusNextPinnedPane", "Next Pinned Pane"),
        ] {
            #expect(
                commandsById[IPCCommandIdentifier(rawValue: commandID)]
                    == IPCCommandListEntry(
                        id: IPCCommandIdentifier(rawValue: commandID), title: title,
                        executionModes: [.requiresInteractiveInput], targetKinds: [],
                        requiredPrivileges: [.layoutMutate]
                    ))
        }
        let terminalScrollEntries: [IPCCommandListEntry] = [
            ("scrollPageUp", "Scroll Up 90%"),
            ("scrollPageDown", "Scroll Down 90%"),
            ("scrollSmallStepUp", "Scroll Up 33%"),
            ("scrollSmallStepDown", "Scroll Down 33%"),
        ].map { commandID, title in
            IPCCommandListEntry(
                id: IPCCommandIdentifier(rawValue: commandID),
                title: title,
                executionModes: [.requiresInteractiveInput],
                targetKinds: [.pane],
                requiredPrivileges: [.terminalInputWrite]
            )
        }
        let acceptedEntries: [IPCCommandListEntry] =
            [
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "pinRepo"),
                    title: "Pin Repository",
                    executionModes: [.headless],
                    targetKinds: [.repo],
                    requiredPrivileges: [.sidebarStateMutate]
                ),
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "closePane"),
                    title: "Close Pane",
                    executionModes: [.requiresInteractiveInput],
                    targetKinds: [.pane],
                    requiredPrivileges: [.layoutMutate]
                ),
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "showCommandBarEverything"),
                    title: "Quick Find",
                    executionModes: [.uiPresentation],
                    targetKinds: [],
                    requiredPrivileges: [.uiPresent]
                ),
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "focusSidebar"),
                    title: "Focus Sidebar",
                    executionModes: [.uiPresentation],
                    targetKinds: [],
                    requiredPrivileges: [.uiPresent]
                ),
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: "zoomPane"),
                    title: "Pane Zoom",
                    executionModes: [.headless],
                    targetKinds: [.pane],
                    requiredPrivileges: [.layoutMutate]
                ),
            ] + terminalScrollEntries
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for acceptedEntry in acceptedEntries {
            let actualEntry = try #require(commandsById[acceptedEntry.id])

            #expect(actualEntry == acceptedEntry)
            #expect(try encoder.encode(actualEntry) == encoder.encode(acceptedEntry))
        }
    }

    // Mutation caught: interactive surfaces or command-context requirements leak into the public IPC DTO.
    @Test("encoded command list entries exclude interactive presentation policy")
    func encodedCommandListEntriesExcludeInteractivePresentationPolicy() throws {
        let adapter = makeIPCCommandAdapterForPresentationIsolationTests()
        let result = try adapter.listCommands()
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
            "argumentSchema",
        ])
        let interactivePolicyKeys = Set([
            "surfacePolicy",
            "surfaces",
            "targeting",
            "preferredInvocation",
            "visibleWhen",
            "requirements",
        ])

        #expect(!encodedCommands.isEmpty)
        for encodedCommand in encodedCommands {
            #expect(Set(encodedCommand.keys) == expectedEntryKeys)
            #expect(Set(encodedCommand.keys).isDisjoint(with: interactivePolicyKeys))
        }
    }
}
