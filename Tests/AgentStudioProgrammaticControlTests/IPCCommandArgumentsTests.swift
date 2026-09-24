import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC typed command arguments")
struct IPCCommandArgumentsTests {
    @Test("every closed variant has one typed sample and a unique schema branch")
    func everyVariantHasOneTypedSample() throws {
        let samples = try IPCCommandArgumentsTestFixtures.allArguments()
        let sampleVariants = samples.map(\.variant)

        #expect(samples.count == 28)
        #expect(sampleVariants == IPCCommandArgumentVariant.allCases)
        #expect(Set(sampleVariants).count == IPCCommandArgumentVariant.allCases.count)

        let completeSchema = try IPCCommandArguments.ipcSchema(
            allowing: IPCCommandArgumentVariant.allCases
        )
        for sample in samples {
            let encoded = try JSONEncoder().encode(sample)
            let encodedObject = try #require(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            #expect(encodedObject["kind"] as? String == sample.variant.rawValue)
            #expect(
                try completeSchema.decode(IPCCommandArguments.self, from: encoded)
                    == sample
            )
            #expect(
                try IPCCommandArguments.ipcSchema(allowing: [sample.variant])
                    .decode(IPCCommandArguments.self, from: encoded) == sample
            )
            #expect(
                try sample.variant.schema.decode(IPCCommandArguments.self, from: encoded)
                    == sample
            )
        }
    }

    @Test("pane selector preserves each accepted raw spelling")
    func paneSelectorPreservesSharedVocabulary() throws {
        let canonicalPaneId = UUID(uuidString: "01994abc-1000-7000-8000-000000000101")!
        let expected: [(String, IPCTargetSelector)] = [
            ("self", .selfPane),
            (canonicalPaneId.uuidString, .canonical(kind: .pane, id: canonicalPaneId)),
            ("pane:3", .paneOrdinal(3)),
        ]

        for (rawValue, parsed) in expected {
            let selector = try IPCPaneSelector(rawValue: rawValue)
            #expect(selector.rawValue == rawValue)
            #expect(selector.parsed == parsed)
            #expect(
                try IPCPaneSelector.ipcSchema().decode(
                    IPCPaneSelector.self,
                    from: JSONEncoder().encode(selector)
                ) == selector
            )
        }
    }

    @Test("pane selector rejects wrong kinds and malformed ordinals")
    func paneSelectorRejectsWrongKindsAndMalformedValues() throws {
        for wrongKind in ["workspace:2", "window:2", "repo:2", "tab:2"] {
            #expect(throws: IPCTargetSelectorError.wrongTargetKind) {
                try IPCPaneSelector(rawValue: wrongKind)
            }
        }
        for malformed in ["", "focused", "pane:0", "pane:-1", "pane:01"] {
            #expect(throws: IPCTargetSelectorError.invalidSelector) {
                try IPCPaneSelector(rawValue: malformed)
            }
        }
    }

    @Test("role-specific pane selectors cannot be swapped or hidden in unknown fields")
    func roleSpecificPaneSelectorsRejectFieldSwaps() throws {
        let windowId = IPCCommandArgumentsTestFixtures.workspaceWindowId.uuidString
        let destinationTabId = IPCCommandArgumentsTestFixtures.destinationTabId.uuidString
        let moveSchema = try IPCCommandArguments.ipcSchema(allowing: [.movePaneToTab])

        for invalid in [
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "movePaneToTab",
                "workspaceWindowId": windowId,
                "paneSelector": "self",
                "destinationTabId": destinationTabId,
            ]),
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "movePaneToTab",
                "workspaceWindowId": windowId,
                "sourcePaneSelector": "self",
                "tabId": destinationTabId,
            ]),
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "movePaneToTab",
                "workspaceWindowId": windowId,
                "sourcePaneSelector": "self",
                "destinationTabId": destinationTabId,
                "ignored": true,
            ]),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try moveSchema.normalize(invalid)
            }
        }
    }

    @Test("terminal source alternatives are disjoint and reject mixed source roles")
    func terminalSourceAlternativesAreDisjoint() throws {
        let windowId = IPCCommandArgumentsTestFixtures.workspaceWindowId.uuidString
        let worktreeId = IPCCommandArgumentsTestFixtures.worktreeId.uuidString
        let schema = try IPCCommandArguments.ipcSchema(
            allowing: [.terminalFromWorktree, .terminalFromPane]
        )
        let worktree = try IPCCommandArgumentsTestFixtures.encodedObject([
            "kind": "terminalFromWorktree",
            "workspaceWindowId": windowId,
            "worktreeId": worktreeId,
            "launchDirectory": "/tmp/project",
            "title": "Build",
        ])
        let pane = try IPCCommandArgumentsTestFixtures.encodedObject([
            "kind": "terminalFromPane",
            "workspaceWindowId": windowId,
            "sourcePaneSelector": "pane:3",
            "launchDirectory": "/tmp/project",
            "title": "Build",
        ])

        #expect(try schema.decode(IPCCommandArguments.self, from: worktree).variant == .terminalFromWorktree)
        #expect(try schema.decode(IPCCommandArguments.self, from: pane).variant == .terminalFromPane)
        #expect(throws: IPCSchemaValidationError.self) {
            try schema.normalize(
                IPCCommandArgumentsTestFixtures.encodedObject([
                    "kind": "terminalFromWorktree",
                    "workspaceWindowId": windowId,
                    "worktreeId": worktreeId,
                    "sourcePaneSelector": "self",
                ])
            )
        }
    }

    @Test("management source alternatives require their exact pane roles")
    func managementSourceAlternativesRequireExactRoles() throws {
        let windowId = IPCCommandArgumentsTestFixtures.workspaceWindowId.uuidString
        let schema = try IPCCommandArguments.ipcSchema(
            allowing: [.managementFromMainPane, .managementFromDrawerPane]
        )

        for valid in [
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "managementFromMainPane",
                "workspaceWindowId": windowId,
                "mainPaneSelector": "self",
            ]),
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "managementFromDrawerPane",
                "workspaceWindowId": windowId,
                "parentPaneSelector": "pane:2",
                "drawerPaneSelector": "pane:3",
            ]),
        ] {
            _ = try schema.decode(IPCCommandArguments.self, from: valid)
        }
        for invalid in [
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "managementFromMainPane",
                "workspaceWindowId": windowId,
                "parentPaneSelector": "pane:2",
            ]),
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "managementFromDrawerPane",
                "workspaceWindowId": windowId,
                "parentPaneSelector": "pane:2",
            ]),
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "managementFromMainPane",
                "workspaceWindowId": windowId,
                "mainPaneSelector": "self",
                "drawerPaneSelector": "pane:3",
            ]),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.normalize(invalid)
            }
        }
    }

    @Test("a Bridge document names an absolute path; relative paths are refused")
    func bridgeDocumentRequiresAbsolutePath() throws {
        let schema = try IPCCommandArguments.ipcSchema(allowing: [.bridgeDocumentInPane])
        let windowId = IPCCommandArgumentsTestFixtures.workspaceWindowId.uuidString
        let absolute = try IPCCommandArgumentsTestFixtures.encodedObject([
            "kind": "bridgeDocumentInPane",
            "workspaceWindowId": windowId,
            "targetPaneSelector": "self",
            "path": "/tmp/project/notes.md",
        ])
        guard case .bridgeDocumentInPane(let decoded) = try schema.decode(IPCCommandArguments.self, from: absolute)
        else {
            Issue.record("Expected a Bridge document argument")
            return
        }
        #expect(decoded.path == "/tmp/project/notes.md")
        for relativePath in ["notes.md", "./notes.md", "../project/notes.md", "/"] {
            let relative = try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "bridgeDocumentInPane",
                "workspaceWindowId": windowId,
                "targetPaneSelector": "self",
                "path": relativePath,
            ])
            #expect(throws: (any Error).self) {
                try schema.decode(IPCCommandArguments.self, from: relative)
            }
        }
    }

    @Test("no arguments accepts only its discriminant")
    func noArgumentsRejectsPayloadFields() throws {
        let schema = try IPCCommandArguments.ipcSchema(allowing: [.noArguments])
        #expect(
            try schema.decode(
                IPCCommandArguments.self,
                from: Data(#"{"kind":"noArguments"}"#.utf8)
            ) == .noArguments
        )
        for invalid in [
            Data(#"{}"#.utf8),
            Data(#"{"kind":"noArguments","filter":"unread"}"#.utf8),
            Data(#"{"kind":"noArguments","mode":"compact"}"#.utf8),
        ] {
            #expect(throws: IPCSchemaValidationError.self) {
                try schema.normalize(invalid)
            }
        }
    }

    @Test("required identities and scalar types fail with precise schema reasons")
    func requiredIdentitiesAndTypesHavePreciseFailures() throws {
        let windowId = IPCCommandArgumentsTestFixtures.workspaceWindowId.uuidString
        let paneSchema = try IPCCommandArguments.ipcSchema(allowing: [.pane])

        try expectSchemaFailure(
            Data(#"{"kind":"pane","paneSelector":"self"}"#.utf8),
            schema: paneSchema,
            reason: .missingField
        )
        try expectSchemaFailure(
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "pane",
                "workspaceWindowId": windowId,
                "paneSelector": "workspace:2",
            ]),
            schema: paneSchema,
            reason: .invalidValue
        )
        try expectSchemaFailure(
            try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "pane",
                "workspaceWindowId": windowId,
                "paneSelector": 3,
            ]),
            schema: paneSchema,
            reason: .wrongType
        )
        try expectSchemaFailure(
            Data(#"{"kind":"repository","repoId":"not-a-uuid"}"#.utf8),
            schema: try IPCCommandArguments.ipcSchema(allowing: [.repository]),
            reason: .invalidValue
        )
    }

    @Test("constant defaults materialize while dynamic defaults remain omitted")
    func constantAndDynamicDefaultsRemainDistinct() throws {
        let windowId = IPCCommandArgumentsTestFixtures.workspaceWindowId.uuidString
        let webviewSchema = try IPCCommandArguments.ipcSchema(allowing: [.webview])
        let webview = try webviewSchema.decode(
            IPCCommandArguments.self,
            from: try IPCCommandArgumentsTestFixtures.encodedObject([
                "kind": "webview",
                "workspaceWindowId": windowId,
            ])
        )
        #expect(
            webview
                == .webview(
                    IPCWebviewCommandArguments(
                        workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                        url: "https://github.com"
                    )
                )
        )

        let dynamicDefaultCases: [DynamicDefaultCase] = [
            DynamicDefaultCase(
                variant: .newTab,
                object: ["kind": "newTab", "workspaceWindowId": windowId],
                omittedFields: ["launchDirectory"],
                expected: .newTab(
                    IPCNewTabCommandArguments(
                        workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                        launchDirectory: nil
                    )
                )
            ),
            DynamicDefaultCase(
                variant: .terminalFromWorktree,
                object: [
                    "kind": "terminalFromWorktree",
                    "workspaceWindowId": windowId,
                    "worktreeId": IPCCommandArgumentsTestFixtures.worktreeId.uuidString,
                ],
                omittedFields: ["launchDirectory", "title"],
                expected: .terminalFromWorktree(
                    IPCTerminalFromWorktreeCommandArguments(
                        workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                        worktreeId: IPCCommandArgumentsTestFixtures.worktreeId,
                        launchDirectory: nil,
                        title: nil
                    )
                )
            ),
            DynamicDefaultCase(
                variant: .terminalFromPane,
                object: [
                    "kind": "terminalFromPane",
                    "workspaceWindowId": windowId,
                    "sourcePaneSelector": "self",
                ],
                omittedFields: ["launchDirectory", "title"],
                expected: .terminalFromPane(
                    IPCTerminalFromPaneCommandArguments(
                        workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                        sourcePaneSelector: try IPCCommandArgumentsTestFixtures.paneSelector("self"),
                        launchDirectory: nil,
                        title: nil
                    )
                )
            ),
            DynamicDefaultCase(
                variant: .floatingTerminal,
                object: ["kind": "floatingTerminal", "workspaceWindowId": windowId],
                omittedFields: ["launchDirectory", "title"],
                expected: .floatingTerminal(
                    IPCFloatingTerminalCommandArguments(
                        workspaceWindowId: IPCCommandArgumentsTestFixtures.workspaceWindowId,
                        launchDirectory: nil,
                        title: nil
                    )
                )
            ),
        ]
        for fixture in dynamicDefaultCases {
            let normalized = try IPCCommandArguments.ipcSchema(allowing: [fixture.variant])
                .normalize(IPCCommandArgumentsTestFixtures.encodedObject(fixture.object))
            let normalizedObject = try #require(
                JSONSerialization.jsonObject(with: normalized) as? [String: Any]
            )
            for field in fixture.omittedFields {
                #expect(normalizedObject[field] == nil)
            }
            #expect(try JSONDecoder().decode(IPCCommandArguments.self, from: normalized) == fixture.expected)
        }
    }

    @Test("single and multiple allowed variants keep exact union cardinality")
    func allowedVariantSchemaHasExactCardinality() throws {
        let paneSample = try #require(
            IPCCommandArgumentsTestFixtures.allArguments().first { $0.variant == .pane }
        )
        let paneData = try JSONEncoder().encode(paneSample)

        #expect(
            try IPCCommandArguments.ipcSchema(allowing: [.pane])
                .decode(IPCCommandArguments.self, from: paneData) == paneSample
        )
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandArguments.ipcSchema(allowing: [.tab])
                .normalize(paneData)
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandArguments.ipcSchema(allowing: [])
        }
        #expect(throws: IPCSchemaValidationError.self) {
            try IPCCommandArguments.ipcSchema(allowing: [.pane, .pane])
        }
    }

    private func expectSchemaFailure(
        _ data: Data,
        schema: IPCJSONSchema,
        reason: IPCSchemaValidationError.Reason
    ) throws {
        do {
            _ = try schema.normalize(data)
            Issue.record("Expected schema validation to fail")
        } catch let failure as IPCSchemaValidationError {
            #expect(failure.reason == reason)
        }
    }
}

private struct DynamicDefaultCase {
    let variant: IPCCommandArgumentVariant
    let object: [String: Any]
    let omittedFields: [String]
    let expected: IPCCommandArguments
}
