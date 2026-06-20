import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC registry and authorization")
struct AgentStudioIPCRegistryAuthorizationTests {
    @Test("phase-one registry has complete metadata and no deferred namespaces")
    func phaseOneRegistryHasCompleteMetadataAndNoDeferredNamespaces() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let forbiddenPrefixes = ["zmx.", "mcp.", "browser.", "webview.", "orchestration."]

        #expect(registry.definitions.count == 47)
        for definition in registry.definitions {
            #expect(!definition.paramsSchema.name.isEmpty)
            #expect(!definition.resultSchema.name.isEmpty)
            #expect(!definition.privilegeClasses.isEmpty)
            #expect(!forbiddenPrefixes.contains { definition.name.hasPrefix($0) })
        }

        let commandList = try #require(registry.definition(named: "command.list"))
        #expect(commandList.privilegeClasses == [.systemRead])
        #expect(commandList.executionOwner == .queryReader)

        let commandExecute = try #require(registry.definition(named: "command.execute"))
        #expect(commandExecute.privilegeClasses == [.debugUnsafe])
        #expect(commandExecute.executionOwner == .appCommand)

        let commandBarOpen = try #require(registry.definition(named: "ui.commandBar.open"))
        #expect(commandBarOpen.privilegeClasses == [.uiPresent])
        #expect(commandBarOpen.executionOwner == .uiPresentation)

        for methodName in ["pane.split", "pane.close", "drawer.toggle", "drawer.addPane"] {
            let definition = try #require(registry.definition(named: methodName))
            #expect(definition.privilegeClasses == [.layoutMutate])
            #expect(definition.executionOwner == .workspaceAction)
        }

        let expectedBridgeMethods: [String: (privileges: Set<String>, owner: String)] = [
            "bridge.diff.load": (["layoutMutate"], "bridgeCapability"),
            "bridge.diff.refresh": (["bridgeControl"], "bridgeCapability"),
            "bridge.diff.getPackage": (["bridgeRead"], "bridgeCapability"),
            "bridge.diff.renderState": (["bridgeRead"], "bridgeCapability"),
            "bridge.diff.selectFile": (["bridgeControl"], "bridgeCapability"),
            "bridge.diff.scrollToFile": (["bridgeControl"], "bridgeCapability"),
            "bridge.diff.expandFile": (["bridgeControl"], "bridgeCapability"),
            "bridge.diff.collapseFile": (["bridgeControl"], "bridgeCapability"),
            "bridge.fileTree.search": (["bridgeControl"], "bridgeCapability"),
            "bridge.fileTree.setFilter": (["bridgeControl"], "bridgeCapability"),
            "bridge.fileTree.revealPath": (["bridgeControl"], "bridgeCapability"),
            "bridge.fileView.getContent": (["bridgeContentRead"], "bridgeCapability"),
            "bridge.fileView.showMarkdownPreview": (["bridgeControl"], "bridgeCapability"),
            "bridge.telemetry.snapshot": (["bridgeTelemetryRead"], "bridgeCapability"),
            "bridge.telemetry.flush": (["bridgeTelemetryFlush"], "bridgeCapability"),
        ]
        for (methodName, expected) in expectedBridgeMethods {
            let definition = try #require(registry.definition(named: methodName))
            #expect(Set(definition.privilegeClasses.map(\.rawValue)) == expected.privileges)
            #expect(definition.executionOwner.rawValue == expected.owner)
        }

        #expect(registry.definition(named: "webview.evaluateJavaScript") == nil)
        #expect(registry.definition(named: "bridge.rawPostMessage") == nil)
        #expect(registry.definition(named: "bridge.review.getPackage") == nil)
        #expect(registry.definition(named: "bridge.content.get") == nil)
    }

    @Test("Bridge diff load is not a baseline self-pane Bridge control method")
    func bridgeDiffLoadIsNotBaselineSelfPaneBridgeControl() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "bridge.diff.load",
                requestedTarget: .selfPane,
                activePaneId: nil
            )
        }
    }

    @Test("Bridge grant checks keep read content control and telemetry scopes distinct")
    func bridgeGrantChecksKeepReadContentControlAndTelemetryScopesDistinct() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let grantLedger = GrantLedger()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAutomationAuthorizationPrincipal()
        let target = IPCTargetScope.pane("pane-1")

        grantLedger.grant(
            IPCPermissionScope(privilege: .bridgeRead, target: target, dataScope: .bridgeReviewPackage),
            to: principal.principalId
        )

        try service.authorize(
            principal: principal,
            methodName: "bridge.diff.getPackage",
            requestedTarget: target,
            activePaneId: nil
        )
        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "bridge.fileView.getContent",
                requestedTarget: target,
                activePaneId: nil
            )
        }
        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "bridge.diff.selectFile",
                requestedTarget: target,
                activePaneId: nil
            )
        }
        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "bridge.telemetry.snapshot",
                requestedTarget: target,
                activePaneId: nil
            )
        }
        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "bridge.telemetry.flush",
                requestedTarget: target,
                activePaneId: nil
            )
        }

        grantLedger.grant(
            IPCPermissionScope(privilege: .bridgeContentRead, target: target, dataScope: .bridgeContent),
            to: principal.principalId
        )
        grantLedger.grant(
            IPCPermissionScope(privilege: .bridgeControl, target: target, dataScope: .bridgeReviewPackage),
            to: principal.principalId
        )
        grantLedger.grant(
            IPCPermissionScope(privilege: .bridgeTelemetryRead, target: target, dataScope: .bridgeTelemetry),
            to: principal.principalId
        )

        try service.authorize(
            principal: principal,
            methodName: "bridge.fileView.getContent",
            requestedTarget: target,
            activePaneId: nil
        )
        try service.authorize(
            principal: principal,
            methodName: "bridge.diff.selectFile",
            requestedTarget: target,
            activePaneId: nil
        )
        try service.authorize(
            principal: principal,
            methodName: "bridge.telemetry.snapshot",
            requestedTarget: target,
            activePaneId: nil
        )
        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "bridge.telemetry.flush",
                requestedTarget: target,
                activePaneId: nil
            )
        }

        grantLedger.grant(
            IPCPermissionScope(privilege: .bridgeTelemetryFlush, target: target, dataScope: .bridgeTelemetry),
            to: principal.principalId
        )

        try service.authorize(
            principal: principal,
            methodName: "bridge.telemetry.flush",
            requestedTarget: target,
            activePaneId: nil
        )
    }

    @Test("authorizes selfPane terminal send from the bound principal pane")
    func authorizesSelfPaneTerminalSendFromBoundPrincipalPane() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        try service.authorize(
            principal: principal,
            methodName: "terminal.send",
            requestedTarget: .selfPane,
            activePaneId: "pane-2"
        )
    }

    @Test("denies cross-pane terminal send without an elevated grant")
    func deniesCrossPaneTerminalSendWithoutElevatedGrant() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "terminal.send",
                requestedTarget: .pane("pane-2"),
                activePaneId: "pane-2"
            )
        }
    }

    @Test("authorizes cross-pane terminal send with a canonical active grant")
    func authorizesCrossPaneTerminalSendWithCanonicalActiveGrant() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let grantLedger = GrantLedger()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        grantLedger.grant(
            IPCPermissionScope(privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput),
            to: principal.principalId
        )

        try service.authorize(
            principal: principal,
            methodName: "terminal.send",
            requestedTarget: .pane("pane-2"),
            activePaneId: "pane-3"
        )
    }

    @Test("requires every privilege on multi-privilege methods")
    func requiresEveryPrivilegeOnMultiPrivilegeMethods() throws {
        let method = try IPCMethodDefinition(
            name: "pane.inspectAndFocus",
            privilegeClasses: [.paneContextRead, .layoutMutate],
            executionOwner: .workspaceAction,
            resultSemantics: .applied
        )
        let grantLedger = GrantLedger()
        let service = AuthorizationService(
            methodRegistry: AppIPCMethodRegistry(definitions: [method]),
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "pane.inspectAndFocus",
                requestedTarget: .selfPane,
                activePaneId: nil
            )
        }

        grantLedger.grant(
            IPCPermissionScope(privilege: .layoutMutate, target: .pane("pane-1"), dataScope: .paneContext),
            to: principal.principalId
        )

        try service.authorize(
            principal: principal,
            methodName: "pane.inspectAndFocus",
            requestedTarget: .selfPane,
            activePaneId: nil
        )
    }

    @Test("command discovery is non-debug while command execution remains unsafe-debug only")
    func commandDiscoveryIsNonDebugWhileCommandExecutionRemainsUnsafeDebugOnly() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let grantLedger = GrantLedger()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let unsafeDebug = IPCPrincipal(
            principalId: UUID(),
            runtimeId: UUID(),
            accessMode: .unsafeDebug,
            kind: .unsafeDebugClient,
            approvalAuthority: .noApprovalAuthority
        )
        let spawnedPane = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        try service.authorize(
            principal: spawnedPane,
            methodName: "command.list",
            requestedTarget: .selfPane,
            activePaneId: nil
        )

        grantLedger.grant(
            IPCPermissionScope(privilege: .debugUnsafe, target: .app, dataScope: .unspecified),
            to: spawnedPane.principalId
        )
        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: spawnedPane,
                methodName: "command.execute",
                requestedTarget: .app,
                activePaneId: "pane-1"
            )
        }

        try service.authorize(
            principal: unsafeDebug,
            methodName: "command.execute",
            requestedTarget: .app,
            activePaneId: nil
        )
    }

    @Test("spawned pane baseline does not include ui presentation")
    func spawnedPaneBaselineDoesNotIncludeUIPresentation() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "ui.commandBar.open",
                requestedTarget: .app,
                activePaneId: nil
            )
        }
    }

    @Test("ui presentation requires app scoped authority")
    func uiPresentationRequiresAppScopedAuthority() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let grantLedger = GrantLedger()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let principal = makeAuthorizationPrincipal(boundPaneId: "pane-1")
        grantLedger.grant(
            IPCPermissionScope(privilege: .uiPresent, target: .pane("pane-1"), dataScope: .uiSurface),
            to: principal.principalId
        )

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: principal,
                methodName: "ui.commandBar.open",
                requestedTarget: .app,
                activePaneId: nil
            )
        }

        grantLedger.grant(
            IPCPermissionScope(privilege: .uiPresent, target: .app, dataScope: .uiSurface),
            to: principal.principalId
        )
        try service.authorize(
            principal: principal,
            methodName: "ui.commandBar.open",
            requestedTarget: .app,
            activePaneId: nil
        )
    }
}

private func makeAuthorizationPrincipal(boundPaneId: String) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: boundPaneId, boundWorkspaceId: nil),
        approvalAuthority: .noApprovalAuthority
    )
}

private func makeAutomationAuthorizationPrincipal() -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .automationClient,
        approvalAuthority: .noApprovalAuthority
    )
}
