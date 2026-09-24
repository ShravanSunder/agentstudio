import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC built-in typed method catalog")
struct IPCBuiltInMethodCatalogTests {
    @Test("catalog exposes exactly 48 unique static methods in name order")
    func catalogHasExactStaticSurface() throws {
        let catalog = try makeCatalog(waitMaximum: 9)
        let names = catalog.erasedDescriptors.map(\.metadata.name)

        #expect(names == expectedStaticMethodNames)
        #expect(Set(names).count == 48)
        #expect(names == names.sorted())
    }

    @Test("every static descriptor carries at least one validated typed example")
    func everyDescriptorHasTypedExamples() throws {
        let catalog = try makeCatalog(waitMaximum: 9)

        for descriptor in catalog.erasedDescriptors {
            #expect(!descriptor.metadata.examples.isEmpty)
            _ = try descriptor.catalogEntrySchema.decode(
                IPCMethodCatalogEntry.self,
                from: JSONEncoder().encode(descriptor.metadata)
            )
        }
    }

    @Test("C4 debug methods and ordinary system auth event methods stay separated")
    func exposureMatchesSettledChannelBoundary() throws {
        let catalog = try makeCatalog(waitMaximum: 9)
        let ordinaryNames = Set(
            catalog.erasedDescriptors
                .filter { $0.metadata.exposure == .allChannels }
                .map(\.metadata.name)
        )

        #expect(ordinaryNames == ordinaryMethodNames)
        #expect(
            catalog.erasedDescriptors
                .filter { !ordinaryMethodNames.contains($0.metadata.name) }
                .allSatisfy { $0.metadata.exposure == .debugTesting }
        )
        #expect(catalog.systemAndAuth.systemPing.principalAvailability == .preAuthentication)
        #expect(catalog.systemAndAuth.authLogin.principalAvailability == .preAuthentication)
        #expect(catalog.systemAndAuth.authStatus.principalAvailability == .preAuthentication)
        #expect(
            catalog.erasedDescriptors.filter { $0.metadata.responseDelivery == .subscription }
                .map(\.metadata.name) == ["events.subscribe"]
        )
    }

    @Test("excluded and dynamic methods do not enter the static catalog")
    func deferredAndDynamicMethodsAreAbsent() throws {
        let names = Set(try makeCatalog(waitMaximum: 9).erasedDescriptors.map(\.metadata.name))
        let excludedNames: Set<String> = [
            "system.capabilities",
            "command.list",
            "command.execute",
            "permission.request",
            "permission.requestStatus",
            "permission.grantStatus",
            "permission.pendingApprovals",
            "permission.resolveRequest",
            "session.bind",
            "file.open",
        ]

        #expect(names.isDisjoint(with: excludedNames))
    }

    @Test("terminal wait uses the caller-supplied maximum in discovery and decoding")
    func terminalWaitUsesInjectedMaximum() throws {
        let suppliedMaximum = 2.5
        let catalog = try makeCatalog(waitMaximum: suppliedMaximum)
        let descriptor = catalog.terminal.terminalWait
        let valid = try descriptor.decodeParameters(
            from: Data(
                #"{"handle":"self","condition":"titleChanged","timeoutSeconds":2.5}"#.utf8
            )
        )
        #expect(valid.timeoutSeconds == suppliedMaximum)
        #expect(throws: IPCSchemaValidationError.self) {
            try descriptor.decodeParameters(
                from: Data(
                    #"{"handle":"self","condition":"titleChanged","timeoutSeconds":2.5001}"#.utf8
                )
            )
        }

        let document = try #require(
            JSONSerialization.jsonObject(
                with: descriptor.contract.parameterSchema.jsonSchemaData()
            ) as? [String: Any]
        )
        let properties = try #require(document["properties"] as? [String: [String: Any]])
        #expect(properties["timeoutSeconds"]?["maximum"] as? Double == suppliedMaximum)
    }

    @Test("Bridge search retains text default and the 4096 UTF-16-unit limit")
    func bridgeSearchPreservesExistingWireRules() throws {
        let catalog = try makeCatalog(waitMaximum: 9)
        let descriptor = catalog.bridge.control.bridgeFileTreeSearch
        let correlationId = fixtureContext.correlationId
        let maximumText = String(repeating: "👋", count: 2048)
        let valid = try descriptor.decodeParameters(
            from: encodedObject([
                "handle": "self",
                "searchText": maximumText,
                "correlationId": correlationId.uuidString,
            ])
        )

        #expect(valid.searchMode == .text)
        #expect(valid.searchText.utf16.count == 4096)
        #expect(throws: IPCSchemaValidationError.self) {
            try descriptor.decodeParameters(
                from: encodedObject([
                    "handle": "self",
                    "searchText": maximumText + "x",
                    "correlationId": correlationId.uuidString,
                ])
            )
        }
    }

    @Test("curated relationship inputs are retained without a command identity table")
    func curatedRelationshipsComeFromInputs() throws {
        let catalog = try makeCatalog(waitMaximum: 9)

        #expect(catalog.layout.paneFocus.commandRelationship == relationships.paneFocus)
        #expect(catalog.layout.paneClose.commandRelationship == relationships.paneClose)
        #expect(catalog.layout.drawerToggle.commandRelationship == relationships.drawerToggle)
        #expect(catalog.layout.drawerAddPane.commandRelationship == relationships.drawerAddPane)
        #expect(catalog.bridge.review.bridgeDiffLoad.commandRelationship == relationships.bridgeDiffLoad)
        #expect(catalog.bridge.review.bridgeFileViewOpen.commandRelationship == relationships.bridgeFileViewOpen)
        #expect(catalog.layout.paneSplit.commandRelationship == .noInteractiveIdentity)
        #expect(catalog.terminal.terminalSend.commandRelationship == .noInteractiveIdentity)
        #expect(catalog.presentationAndSidebar.uiCommandBarOpen.commandRelationship == .noInteractiveIdentity)
    }

    @Test("every mutating descriptor requires correlation in metadata and its example body")
    func mutationsRequireDeclaredCorrelation() throws {
        let catalog = try makeCatalog(waitMaximum: 9)
        let mutatingDescriptors = catalog.erasedDescriptors.filter(\.metadata.isMutating)

        #expect(Set(mutatingDescriptors.map(\.metadata.name)) == mutatingMethodNames)
        for descriptor in mutatingDescriptors {
            #expect(descriptor.metadata.correlationPolicy == .required)
            let metadataObject = try #require(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(descriptor.metadata)
                ) as? [String: Any]
            )
            let examples = try #require(metadataObject["examples"] as? [[String: Any]])
            var parameters = try #require(examples.first?["parameters"] as? [String: Any])
            parameters.removeValue(forKey: "correlationId")
            #expect(throws: IPCSchemaValidationError.self) {
                try descriptor.metadata.parameterSchema.normalize(
                    JSONSerialization.data(withJSONObject: parameters)
                )
            }
        }
    }

    @Test("selected result boundaries distinguish reads admission presentation and applied layout")
    func resultBoundariesMatchOwners() throws {
        let catalog = try makeCatalog(waitMaximum: 9)

        #expect(catalog.terminal.terminalSend.resultSemantics == .accepted)
        #expect(catalog.terminal.terminalWait.resultSemantics == .accepted)
        #expect(catalog.bridge.control.bridgeDiffScrollToFile.resultSemantics == .accepted)
        #expect(catalog.bridge.control.bridgeFileTreeSearch.resultSemantics == .accepted)
        #expect(catalog.presentationAndSidebar.uiCommandBarOpen.resultSemantics == .presented)
        #expect(catalog.presentationAndSidebar.uiArrangementsOpen.resultSemantics == .presented)
        #expect(catalog.layout.paneSplit.resultSemantics == .applied)
        #expect(catalog.bridge.telemetry.bridgeTelemetrySnapshot.resultSemantics == .applied)
    }

    private var relationships: IPCBuiltInMethodRelationshipInputs {
        .init(
            paneFocus: .appCommand(identifier: "fixture.pane-focus"),
            paneClose: .appCommand(identifier: "fixture.pane-close"),
            drawerToggle: .appCommand(identifier: "fixture.drawer-toggle"),
            drawerAddPane: .appCommand(identifier: "fixture.drawer-add"),
            bridgeDiffLoad: .appCommand(identifier: "fixture.bridge-review-open"),
            bridgeFileViewOpen: .appCommand(identifier: "fixture.bridge-files-open")
        )
    }

    private var fixtureContext: IPCBuiltInMethodExampleContext {
        .init(
            runtimeId: UUIDv7.generate(),
            windowId: UUIDv7.generate(),
            workspaceId: UUIDv7.generate(),
            repositoryId: UUIDv7.generate(),
            worktreeId: UUIDv7.generate(),
            tabId: UUIDv7.generate(),
            paneId: UUIDv7.generate(),
            commandId: UUIDv7.generate(),
            correlationId: UUIDv7.generate(),
            subscriptionId: UUIDv7.generate()
        )
    }

    private func makeCatalog(waitMaximum: Double) throws -> IPCBuiltInMethodCatalog {
        try IPCBuiltInMethodCatalog(
            inputs: .init(
                terminalWaitMaximumSeconds: waitMaximum,
                relationships: relationships,
                examples: fixtureContext
            )
        )
    }

    private func encodedObject(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private var ordinaryMethodNames: Set<String> {
        [
            "auth.login",
            "auth.status",
            "events.subscribe",
            "events.unsubscribe",
            "session.event",
            "session.message",
            "session.query",
            "session.report",
            "system.identify",
            "system.ping",
            "system.version",
        ]
    }

    private var mutatingMethodNames: Set<String> {
        [
            "bridge.diff.collapseFile",
            "bridge.diff.expandFile",
            "bridge.diff.load",
            "bridge.diff.refresh",
            "bridge.diff.scrollToFile",
            "bridge.diff.selectFile",
            "bridge.fileTree.revealPath",
            "bridge.fileTree.search",
            "bridge.fileTree.setFilter",
            "bridge.fileView.open",
            "bridge.fileView.showMarkdownPreview",
            "bridge.telemetry.flush",
            "drawer.addPane",
            "drawer.toggle",
            "events.subscribe",
            "events.unsubscribe",
            "pane.close",
            "pane.focus",
            "pane.split",
            "session.event",
            "session.message",
            "session.report",
            "terminal.send",
            "ui.arrangements.open",
            "ui.commandBar.open",
        ]
    }

    private var expectedStaticMethodNames: [String] {
        [
            "auth.login",
            "auth.status",
            "bridge.diff.collapseFile",
            "bridge.diff.expandFile",
            "bridge.diff.getPackage",
            "bridge.diff.load",
            "bridge.diff.refresh",
            "bridge.diff.renderState",
            "bridge.diff.scrollToFile",
            "bridge.diff.selectFile",
            "bridge.fileTree.revealPath",
            "bridge.fileTree.search",
            "bridge.fileTree.setFilter",
            "bridge.fileView.getContent",
            "bridge.fileView.open",
            "bridge.fileView.showMarkdownPreview",
            "bridge.files.search",
            "bridge.telemetry.flush",
            "bridge.telemetry.snapshot",
            "drawer.addPane",
            "drawer.toggle",
            "events.subscribe",
            "events.unsubscribe",
            "pane.close",
            "pane.current",
            "pane.focus",
            "pane.list",
            "pane.snapshot",
            "pane.split",
            "session.event",
            "session.message",
            "session.query",
            "session.report",
            "sidebar.grouping.get",
            "sidebar.surface.get",
            "system.identify",
            "system.ping",
            "system.version",
            "terminal.send",
            "terminal.snapshot",
            "terminal.status",
            "terminal.wait",
            "ui.arrangements.open",
            "ui.commandBar.open",
            "window.current",
            "window.list",
            "workspace.current",
            "workspace.list",
        ]
    }
}
