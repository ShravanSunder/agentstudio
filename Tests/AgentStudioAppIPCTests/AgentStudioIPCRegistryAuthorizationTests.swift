import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC registry and authorization")
struct AgentStudioIPCRegistryAuthorizationTests {
    @Test("phase-one registry has complete metadata and no deferred namespaces")
    func phaseOneRegistryHasCompleteMetadataAndNoDeferredNamespaces() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let forbiddenPrefixes = ["zmx.", "mcp.", "browser.", "webview.", "orchestration."]

        #expect(registry.definitions.count == 49)
        #expect(registry.definition(named: "pane.snapshot") == nil)
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
        #expect(commandExecute.privilegeClasses == [.appCommandExecute])
        #expect(commandExecute.executionOwner == .appCommand)

        let commandBarOpen = try #require(registry.definition(named: "ui.commandBar.open"))
        #expect(commandBarOpen.privilegeClasses == [.uiPresent])
        #expect(commandBarOpen.executionOwner == .uiPresentation)

        #expect(registry.definition(named: "sidebar.grouping.set") == nil)
        #expect(registry.definition(named: "sidebar.surface.set") == nil)

        for methodName in ["sidebar.grouping.get", "sidebar.surface.get"] {
            let definition = try #require(registry.definition(named: methodName))
            #expect(definition.privilegeClasses == [.workspaceRead])
            #expect(definition.executionOwner == .queryReader)
        }

        for methodName in ["pane.split", "pane.close", "drawer.toggle", "drawer.addPane"] {
            let definition = try #require(registry.definition(named: methodName))
            #expect(definition.privilegeClasses == [.layoutMutate])
            #expect(definition.executionOwner == .workspaceAction)
        }

        let expectedBridgeMethods: [String: (privileges: Set<String>, owner: String)] = [
            "bridge.diff.load": (["layoutMutate"], "bridgeCapability"),
            "bridge.fileView.open": (["layoutMutate"], "bridgeCapability"),
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

    @Test("contributed methods merge with base definitions before capability export")
    func contributedMethodsMergeWithBaseDefinitionsBeforeCapabilityExport() throws {
        let baseDefinitions = try AppIPCMethodRegistry.phaseOne().definitions
            .filter { $0.name != "pane.snapshot" }
        let contribution = try makeTestContribution(methodName: "pane.snapshot")

        let registry = try AppIPCMethodRegistry(baseDefinitions: baseDefinitions, contributions: [contribution])

        #expect(registry.definitions.count == baseDefinitions.count + 1)
        #expect(registry.definition(named: "pane.snapshot")?.name == "pane.snapshot")
        #expect(registry.contribution(named: "pane.snapshot")?.definition.name == "pane.snapshot")
        #expect(registry.definitions.map(\.name).sorted() == registry.definitions.map(\.name))
    }

    @Test("registry rejects duplicate base and contributed method names")
    func registryRejectsDuplicateBaseAndContributedMethodNames() throws {
        let method = try makeTestMethodDefinition(name: "pane.snapshot")
        let contribution = try makeTestContribution(methodName: "pane.snapshot")

        #expect(throws: AppIPCMethodRegistryError.self) {
            _ = try AppIPCMethodRegistry(baseDefinitions: [method, method], contributions: [])
        }
        #expect(throws: AppIPCMethodRegistryError.self) {
            _ = try AppIPCMethodRegistry(baseDefinitions: [method], contributions: [contribution])
        }
        #expect(throws: AppIPCMethodRegistryError.self) {
            _ = try AppIPCMethodRegistry(
                baseDefinitions: [],
                contributions: [contribution, contribution]
            )
        }
    }

    @Test("registry rejects deferred and base-owned contributed namespaces")
    func registryRejectsDeferredAndBaseOwnedContributedNamespaces() throws {
        #expect(throws: IPCMethodDefinitionError.self) {
            _ = try makeTestContribution(methodName: "zmx.example")
        }

        let rejectedPrefixes = [
            "bridge", "diff", "review", "mcp", "browser", "webview", "orchestration",
            "system", "auth", "permission", "events", "command", "ui", "terminal", "workspace", "drawer",
        ]

        for prefix in rejectedPrefixes {
            let contribution = try makeTestContribution(methodName: "\(prefix).example")
            #expect(throws: AppIPCMethodRegistryError.self) {
                _ = try AppIPCMethodRegistry(baseDefinitions: [], contributions: [contribution])
            }
        }
    }

    @Test("registry rejects contributed pre-authentication methods")
    func registryRejectsContributedPreAuthenticationMethods() throws {
        let contribution = try makeTestContribution(
            methodName: "pane.preAuthExample",
            principalAvailability: .preAuthentication
        )

        #expect(throws: AppIPCMethodRegistryError.self) {
            _ = try AppIPCMethodRegistry(baseDefinitions: [], contributions: [contribution])
        }
    }

    @Test("registry rejects contributed execution owners outside query reader")
    func registryRejectsContributedExecutionOwnersOutsideQueryReader() throws {
        let contribution = try makeTestContribution(
            methodName: "pane.workspaceAction",
            executionOwner: .workspaceAction
        )

        #expect(throws: AppIPCMethodRegistryError.self) {
            _ = try AppIPCMethodRegistry(baseDefinitions: [], contributions: [contribution])
        }
    }

    @Test("contributed method security contract must be explicit")
    func contributedMethodSecurityContractMustBeExplicit() throws {
        #expect(throws: AppIPCMethodContributionError.self) {
            _ = try makeTestContribution(
                methodName: "pane.noTargetVocabulary",
                targetVocabulary: []
            )
        }
        #expect(throws: AppIPCMethodContributionError.self) {
            _ = try makeTestContribution(
                methodName: "pane.noDataScopes",
                dataScopes: []
            )
        }
        #expect(throws: AppIPCMethodContributionError.self) {
            _ = try makeTestContribution(
                methodName: "pane.noSensitiveDataExclusions",
                sensitiveDataExclusions: []
            )
        }
    }

    @Test("registry rejects contributed data scopes outside security contract")
    func registryRejectsContributedDataScopesOutsideSecurityContract() throws {
        let contribution = try makeTestContribution(
            methodName: "pane.badScope",
            dataScopes: [.bridgeContent]
        )

        #expect(throws: AppIPCMethodRegistryError.self) {
            _ = try AppIPCMethodRegistry(baseDefinitions: [], contributions: [contribution])
        }
    }

    @Test("unsafe debug does not authorize non-allowlisted contributed methods")
    func unsafeDebugDoesNotAuthorizeNonAllowlistedContributedMethods() throws {
        let contribution = try makeTestContribution(methodName: "pane.experimentalRead")
        let registry = try AppIPCMethodRegistry(baseDefinitions: [], contributions: [contribution])
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let unsafeDebug = IPCPrincipal(
            principalId: UUID(),
            runtimeId: UUID(),
            accessMode: .unsafeDebug,
            kind: .unsafeDebugClient,
            approvalAuthority: .noApprovalAuthority
        )

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: unsafeDebug,
                methodName: "pane.experimentalRead",
                requestedTarget: .pane(UUID().uuidString),
                activePaneId: nil
            )
        }
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

    @Test("command discovery is non-debug while command execution accepts neutral app command grants")
    func commandDiscoveryIsNonDebugWhileCommandExecutionAcceptsNeutralAppCommandGrants() throws {
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
        let automation = IPCPrincipal(
            principalId: UUID(),
            runtimeId: UUID(),
            accessMode: .unsafeDebug,
            kind: .automationClient,
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
            IPCPermissionScope(privilege: .appCommandExecute, target: .app, dataScope: .unspecified),
            to: spawnedPane.principalId
        )
        try service.authorize(
            principal: spawnedPane,
            methodName: "command.execute",
            requestedTarget: .app,
            activePaneId: "pane-1"
        )

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: unsafeDebug,
                methodName: "command.execute",
                requestedTarget: .app,
                activePaneId: nil
            )
        }

        #expect(throws: AuthorizationError.self) {
            try service.authorize(
                principal: automation,
                methodName: "command.execute",
                requestedTarget: .app,
                activePaneId: nil
            )
        }
        grantLedger.grant(
            IPCPermissionScope(privilege: .appCommandExecute, target: .app, dataScope: .unspecified),
            to: automation.principalId
        )
        try service.authorize(
            principal: automation,
            methodName: "command.execute",
            requestedTarget: .app,
            activePaneId: nil
        )
    }

    @Test("sidebar semantic methods stay automation-only even with app scoped grants")
    func sidebarSemanticMethodsStayAutomationOnlyEvenWithAppScopedGrants() throws {
        let registry = try AppIPCMethodRegistry.phaseOne()
        let grantLedger = GrantLedger()
        let service = AuthorizationService(
            methodRegistry: registry,
            grantLedger: grantLedger,
            canonicalizer: PermissionScopeCanonicalizer()
        )
        let spawnedPane = makeAuthorizationPrincipal(boundPaneId: "pane-1")
        let automation = IPCPrincipal(
            principalId: UUID(),
            runtimeId: UUID(),
            accessMode: .unsafeDebug,
            kind: .automationClient,
            approvalAuthority: .noApprovalAuthority
        )

        grantLedger.grant(
            IPCPermissionScope(privilege: .workspaceRead, target: .app, dataScope: .unspecified),
            to: spawnedPane.principalId
        )

        for methodName in ["sidebar.grouping.get", "sidebar.surface.get"] {
            #expect(throws: AuthorizationError.self) {
                try service.authorize(
                    principal: spawnedPane,
                    methodName: methodName,
                    requestedTarget: .app,
                    activePaneId: "pane-1"
                )
            }

            #expect(throws: AuthorizationError.self) {
                try service.authorize(
                    principal: automation,
                    methodName: methodName,
                    requestedTarget: .app,
                    activePaneId: nil
                )
            }
            grantLedger.grant(
                IPCPermissionScope(privilege: .workspaceRead, target: .app, dataScope: .unspecified),
                to: automation.principalId
            )
            try service.authorize(
                principal: automation,
                methodName: methodName,
                requestedTarget: .app,
                activePaneId: nil
            )
            grantLedger.revokeAll(for: automation.principalId)
        }
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

private func makeTestMethodDefinition(
    name: String,
    principalAvailability: IPCPrincipalAvailability = .authenticated,
    executionOwner: IPCExecutionOwner = .queryReader
) throws -> IPCMethodDefinition {
    try IPCMethodDefinition(
        name: name,
        paramsSchema: IPCSchemaDescription(name: "\(name).params"),
        resultSchema: IPCSchemaDescription(name: "\(name).result"),
        privilegeClasses: [.paneContextRead],
        principalAvailability: principalAvailability,
        executionOwner: executionOwner,
        resultSemantics: .applied
    )
}

private func makeTestContribution(
    methodName: String,
    principalAvailability: IPCPrincipalAvailability = .authenticated,
    executionOwner: IPCExecutionOwner = .queryReader,
    targetVocabulary: Set<AppIPCContributionTargetVocabulary> = [.pane],
    dataScopes: Set<IPCDataScope> = [.paneContext],
    sensitiveDataExclusions: Set<String> = [
        "cwd",
        "rawTerminalOutput",
        "zmxSessionIdentifier",
    ]
) throws -> AppIPCMethodContribution {
    try AppIPCMethodContribution(
        definition: makeTestMethodDefinition(
            name: methodName,
            principalAvailability: principalAvailability,
            executionOwner: executionOwner
        ),
        securityContract: AppIPCContributionSecurityContract(
            targetVocabulary: targetVocabulary,
            dataScopes: dataScopes,
            sensitiveDataExclusions: sensitiveDataExclusions
        ),
        authorizationContext: { request, _, _ in
            AppIPCAuthorizedRequestContext(request: request, target: .pane(UUID().uuidString))
        },
        dispatch: { _, _, _ in
            .object([:])
        }
    )
}
