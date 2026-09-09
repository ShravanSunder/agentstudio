import AgentStudioProgrammaticControl
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("AgentStudio IPC command presentation isolation")
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

        #expect(
            encodedCommandListSHA256
                == "cc8cb6b4f61899bc3b590b2aed044a49ab04457e262747f2027f09cb3510c166"
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
        #expect(AppCommand.showViewer.ipcSpec.exposure == .notExposed)

        #expect(AppCommand.closePane.ipcSpec.argumentContract == .noArguments)
        #expect(
            AppCommand.setRepoSidebarSortOrder.ipcSpec.argumentContract
                == .repoSidebarSortOrder
        )
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
        let defaultRequest = AppCommandExecutionRequest(command: .showWorktreeSidebar)
        let noArguments = try AppCommandExecutionArguments.commandOwnedArguments(
            contract: .noArguments,
            rawArguments: [:],
            argumentsContainOnlyStrings: true
        )
        let sortOrder = try AppCommandExecutionArguments.commandOwnedArguments(
            contract: .repoSidebarSortOrder,
            rawArguments: ["order": "descending"],
            argumentsContainOnlyStrings: true
        )

        #expect(defaultRequest.arguments == .noArguments)
        #expect(noArguments == .noArguments)
        #expect(sortOrder == .repoSidebarSortOrder(.descending))
    }

    // Mutation caught: the presentation-policy migration changes accepted public command metadata or encoding.
    @Test("representative public IPC metadata remains byte and value equivalent")
    func representativePublicIPCMetadataRemainsByteAndValueEquivalent() throws {
        let adapter = makeIPCCommandAdapterForPresentationIsolationTests()
        let result = try adapter.listCommands()
        let commandsById = Dictionary(uniqueKeysWithValues: result.commands.map { ($0.id, $0) })
        let acceptedEntries: [IPCCommandListEntry] = [
            IPCCommandListEntry(
                id: IPCCommandIdentifier(rawValue: "addRepoFavorite"),
                title: "Add Favorite",
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
                id: IPCCommandIdentifier(rawValue: "zoomPane"),
                title: "Pane Zoom",
                executionModes: [.headless],
                targetKinds: [.pane],
                requiredPrivileges: [.layoutMutate]
            ),
        ]
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
