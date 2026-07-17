import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC programmatic-control contracts")
struct IPCContractsTests {
    @Test("models pane-bound principals with delegated approval authority")
    func modelsPaneBoundPrincipalsWithDelegatedApprovalAuthority() throws {
        let runtimeId = UUID()
        let principalId = UUID()
        let scope = IPCApprovalScope(privilege: .terminalInputWrite, target: .selfPane, dataScope: .terminalInput)

        let principal = IPCPrincipal(
            principalId: principalId,
            runtimeId: runtimeId,
            accessMode: .agentStudioOnly,
            kind: .spawnedPaneAgent(boundPaneId: "pane-1", boundWorkspaceId: nil),
            approvalAuthority: .delegatedApprover(scopes: [scope])
        )

        #expect(principal.principalId == principalId)
        #expect(principal.runtimeId == runtimeId)
        #expect(principal.kind == .spawnedPaneAgent(boundPaneId: "pane-1", boundWorkspaceId: nil))
        #expect(principal.approvalAuthority == .delegatedApprover(scopes: [scope]))
    }

    @Test("method definitions declare privilege owner and result semantics")
    func methodDefinitionsDeclarePrivilegeOwnerAndResultSemantics() throws {
        let definition = try IPCMethodDefinition(
            name: "terminal.send",
            privilegeClasses: [.terminalInputWrite],
            executionOwner: .runtimeCommand,
            resultSemantics: .applied
        )

        #expect(definition.name == "terminal.send")
        #expect(definition.privilegeClasses == [.terminalInputWrite])
        #expect(definition.executionOwner == .runtimeCommand)
        #expect(definition.resultSemantics == .applied)
    }

    @Test("rejects public zmx methods")
    func rejectsPublicZmxMethods() throws {
        #expect(throws: IPCMethodDefinitionError.self) {
            try IPCMethodDefinition(
                name: "zmx.attach",
                privilegeClasses: [.debugUnsafe],
                executionOwner: .runtimeCommand,
                resultSemantics: .applied
            )
        }
    }

    @Test("parses friendly and canonical handles")
    func parsesFriendlyAndCanonicalHandles() throws {
        let uuid = UUID()

        #expect(try IPCHandle.parse("pane:1") == IPCHandle(kind: .pane, reference: .friendlyOrdinal(1)))
        #expect(
            try IPCHandle.parse("repo:\(uuid.uuidString)")
                == IPCHandle(kind: .repo, reference: .canonicalUUID(uuid))
        )
        #expect(
            try IPCHandle.parse("workspace:\(uuid.uuidString)")
                == IPCHandle(kind: .workspace, reference: .canonicalUUID(uuid))
        )
    }

    @Test("rejects invalid handles")
    func rejectsInvalidHandles() throws {
        #expect(throws: IPCHandleError.self) {
            try IPCHandle.parse("pane:0")
        }
        #expect(throws: IPCHandleError.self) {
            try IPCHandle.parse("zmx:1")
        }
    }

    @Test("exports stable event names and codable event payloads")
    func exportsStableEventNamesAndCodableEventPayloads() throws {
        let requestId = UUID()
        let principalId = UUID()
        let approverId = UUID()
        let payload = IPCPermissionEventPayload(
            requestId: requestId,
            state: .pending,
            principalId: principalId,
            requestedScope: IPCPermissionScope(
                privilege: .terminalInputWrite,
                target: .pane("pane-2"),
                dataScope: .terminalInput
            ),
            approvalRoute: .delegatedPrincipal(approverId)
        )
        let notification = IPCPermissionEventNotification(
            eventId: UUID(),
            name: .permissionRequestCreated,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            payload: payload
        )

        let decoded = try JSONDecoder().decode(
            IPCPermissionEventNotification.self,
            from: try JSONEncoder().encode(notification)
        )

        #expect(decoded == notification)
        #expect(
            try JSONDecoder().decode(
                IPCEventNotification.self,
                from: try JSONEncoder().encode(notification.eventNotification)
            ) == notification.eventNotification
        )

        let terminalNotification = IPCEventNotification(
            eventId: UUID(),
            name: .terminalCommandFinished,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_001),
            payload: .terminal(
                IPCTerminalEventPayload(
                    paneId: UUID(),
                    condition: .commandFinished,
                    commandId: UUID(),
                    correlationId: UUID(),
                    exitCode: 0,
                    duration: 1.25
                )
            )
        )
        #expect(
            try JSONDecoder().decode(
                IPCEventNotification.self,
                from: try JSONEncoder().encode(terminalNotification)
            ) == terminalNotification
        )
        #expect(IPCEventName.allCases.map(\.rawValue).contains("permission.requestResolved"))
        #expect(IPCEventName.allCases.map(\.rawValue).contains("terminal.commandFinished"))
        #expect(!IPCEventName.allCases.map(\.rawValue).contains { $0.hasPrefix("zmx.") })
    }
}
