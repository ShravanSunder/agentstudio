import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC programmatic-control contracts")
struct IPCContractsTests {
    @Test("Review comparison commit targets require exact hexadecimal OIDs")
    func reviewComparisonCommitTargetsRequireExactHexadecimalOIDs() throws {
        let validOID = "0123456789abcdef0123456789abcdef01234567"

        #expect(
            try JSONDecoder().decode(
                IPCBridgeReviewComparisonTarget.self,
                from: Data(#"{"kind":"commit","oid":"0123456789abcdef0123456789abcdef01234567"}"#.utf8)
            ) == .commit(oid: validOID)
        )
        for invalidOID in ["abc123", String(repeating: "g", count: 40)] {
            #expect(throws: Error.self) {
                _ = try JSONDecoder().decode(
                    IPCBridgeReviewComparisonTarget.self,
                    from: Data(#"{"kind":"commit","oid":"\#(invalidOID)"}"#.utf8)
                )
            }
        }
    }

    @Test("arrangements presentation contracts round trip optional pane context")
    func arrangementsPresentationContractsRoundTripOptionalPaneContext() throws {
        let correlationId = UUID()
        let workspaceWindowId = UUID()
        let tabId = UUID()
        let paneId = UUID()
        let params = IPCArrangementsOpenParams(
            targetPaneHandle: "pane:\(paneId.uuidString)",
            correlationId: correlationId
        )
        let result = IPCArrangementsOpenResult(
            workspaceWindowId: workspaceWindowId,
            tabId: tabId,
            contextPaneId: paneId,
            correlationId: correlationId
        )

        #expect(
            try JSONDecoder().decode(
                IPCArrangementsOpenParams.self,
                from: JSONEncoder().encode(params)
            ) == params
        )
        #expect(
            try JSONDecoder().decode(
                IPCArrangementsOpenResult.self,
                from: JSONEncoder().encode(result)
            ) == result
        )
    }

    @Test("command argument string validation is decoder-derived")
    func commandArgumentStringValidationIsDecoderDerived() throws {
        let constructed = IPCCommandExecuteParams(
            commandId: .init(rawValue: "setRepoSidebarVisibilityMode"),
            targetHandle: nil,
            arguments: ["mode": "favoritesOnly"]
        )
        let decoded = try JSONDecoder().decode(
            IPCCommandExecuteParams.self,
            from: Data(
                #"{"commandId":"setRepoSidebarVisibilityMode","arguments":{"mode":1}}"#.utf8
            )
        )

        #expect(constructed.argumentsContainOnlyStrings)
        #expect(decoded.arguments.isEmpty)
        #expect(!decoded.argumentsContainOnlyStrings)
    }

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

    @Test("bridge render state keeps diagnostics probes optional when omitted")
    func bridgeRenderStateKeepsDiagnosticsProbesOptionalWhenOmitted() throws {
        let paneId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let payload = """
            {
              "paneId": "\(paneId.uuidString)",
              "summary": {
                "pageTitle": "AgentStudio Bridge",
                "hasAppRoot": true,
                "hasEmptyShell": false,
                "hasReviewShell": true,
                "sidebarPosition": "right"
              },
              "diagnostics": {
                "evaluateSucceeded": true,
                "pageErrorCount": 0,
                "pageErrorKinds": [],
                "pageErrorMessages": [],
                "nativeActivity": "foreground",
                "foregroundWorkEpoch": 1,
                "dirtyFactPresent": false,
                "activeRefreshPassPresent": false,
                "refreshPassCount": 0,
                "productSession": {
                  "activeProducerCount": 0,
                  "activeProducerTaskCount": 0,
                  "activeContentLeaseCount": 0,
                  "queuedFrameCount": 0,
                  "queuedByteCount": 0,
                  "pendingFrameWaiterCount": 0,
                  "inFlightFrameReceiptCount": 0,
                  "pendingLifecycleAcknowledgementCount": 0,
                  "nextMetadataStreamSequence": 0
                }
              }
            }
            """

        let result = try JSONDecoder().decode(IPCBridgeRenderStateResult.self, from: Data(payload.utf8))

        #expect(result.paneId == paneId)
        #expect(result.summary.visibleHydrationStateProbe == nil)
        #expect(result.summary.visibleHydrationDiscardProbe == nil)
        #expect(result.summary.frameJankProbe == nil)
        #expect(result.visibleHydrationStateProbe == nil)
        #expect(result.visibleHydrationDiscardProbe == nil)
        #expect(result.frameJankProbe == nil)
    }

    @Test("bridge file tree search page-control command encodes web search mode")
    func bridgeFileTreeSearchPageControlCommandEncodesWebSearchMode() throws {
        let encoded = try JSONEncoder().encode(
            IPCBridgePageControlCommand.fileTreeSearch(searchText: "BridgePaneController")
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let searchMode = try #require(object["searchMode"] as? [String: Any])

        #expect(object["method"] as? String == "bridge.fileTree.search")
        #expect(object["searchText"] as? String == "BridgePaneController")
        #expect(searchMode["kind"] as? String == "text")
    }

    @Test("bridge file tree search params default to web text search mode")
    func bridgeFileTreeSearchParamsDefaultToWebTextSearchMode() throws {
        let payload = """
            {
              "handle": "pane:1",
              "searchText": "BridgePaneController"
            }
            """

        let params = try JSONDecoder().decode(
            IPCBridgeFileTreeSearchParams.self,
            from: Data(payload.utf8)
        )

        #expect(params.searchMode == .text)
    }

    @Test("bridge file tree search params reject more than 4,096 UTF-16 units")
    func bridgeFileTreeSearchParamsRejectOversizedUTF16Input() throws {
        let admittedPayload = try JSONSerialization.data(withJSONObject: [
            "handle": "pane:1",
            "searchText": String(repeating: "🧭", count: 2048),
        ])
        let rejectedPayload = try JSONSerialization.data(withJSONObject: [
            "handle": "pane:1",
            "searchText": String(repeating: "🧭", count: 2048) + "a",
        ])

        let admitted = try JSONDecoder().decode(
            IPCBridgeFileTreeSearchParams.self,
            from: admittedPayload
        )

        #expect(admitted.searchText.utf16.count == 4096)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                IPCBridgeFileTreeSearchParams.self,
                from: rejectedPayload
            )
        }
    }

    @Test("bridge file tree filter command encodes one surface-discriminated candidate")
    func bridgeFileTreeFilterCommandEncodesSurfaceDiscriminatedCandidate() throws {
        let reviewCommand = IPCBridgePageControlCommand.fileTreeSetFilter(
            candidate: .review(
                gitStatusFilter: .modified,
                categoryFilter: .source,
                showBinary: true,
                showLarge: false
            )
        )
        let encoded = try JSONEncoder().encode(reviewCommand)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let filter = try #require(object["filter"] as? [String: Any])

        #expect(object["method"] as? String == "bridge.fileTree.setFilter")
        #expect(filter["surface"] as? String == "review")
        #expect(filter["gitStatusFilter"] as? String == "modified")
        #expect(filter["categoryFilter"] as? String == "source")
        #expect(filter["showBinary"] as? Bool == true)
        #expect(filter["showLarge"] as? Bool == false)
    }

    @Test("bridge file tree filter params reject the legacy combined shape")
    func bridgeFileTreeFilterParamsRejectLegacyCombinedShape() throws {
        let legacyPayload = """
            {
              "handle": "pane:1",
              "gitStatusFilter": "modified",
              "fileClassFilter": "source"
            }
            """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                IPCBridgeFileTreeSetFilterParams.self,
                from: Data(legacyPayload.utf8)
            )
        }
    }

    @Test("bridge file tree filter params reject undeclared top-level fields")
    func bridgeFileTreeFilterParamsRejectUndeclaredTopLevelFields() throws {
        let invalidPayloads = [
            """
            {
              "handle": "pane:1",
              "candidate": {
                "surface": "files",
                "categoryFilter": "source"
              },
              "fileClassFilter": "source"
            }
            """,
            """
            {
              "handle": "pane:1",
              "candidate": {
                "surface": "review",
                "gitStatusFilter": "modified",
                "categoryFilter": "source",
                "showBinary": true,
                "showLarge": true
              },
              "gitStatusFilter": "modified"
            }
            """,
            """
            {
              "handle": "pane:1",
              "candidate": {
                "surface": "files",
                "categoryFilter": "source"
              },
              "showHidden": true
            }
            """,
        ]

        for invalidPayload in invalidPayloads {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(
                    IPCBridgeFileTreeSetFilterParams.self,
                    from: Data(invalidPayload.utf8)
                )
            }
        }
    }

    @Test("bridge Files filter candidate rejects Review-only fields")
    func bridgeFilesFilterCandidateRejectsReviewOnlyFields() throws {
        let invalidPayload = """
            {
              "surface": "files",
              "categoryFilter": "source",
              "gitStatusFilter": "modified",
              "showBinary": true,
              "showLarge": false
            }
            """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                IPCBridgeFileTreeFilterCandidate.self,
                from: Data(invalidPayload.utf8)
            )
        }
    }

    @Test("bridge Files filter candidate rejects undeclared fields")
    func bridgeFilesFilterCandidateRejectsUndeclaredFields() throws {
        let invalidPayload = """
            {
              "surface": "files",
              "categoryFilter": "source",
              "showHidden": true
            }
            """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                IPCBridgeFileTreeFilterCandidate.self,
                from: Data(invalidPayload.utf8)
            )
        }
    }

    @Test("bridge Review filter candidate rejects legacy fields")
    func bridgeReviewFilterCandidateRejectsLegacyFields() throws {
        let invalidPayload = """
            {
              "surface": "review",
              "gitStatusFilter": "modified",
              "categoryFilter": "source",
              "showBinary": true,
              "showLarge": false,
              "fileClassFilter": "source"
            }
            """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                IPCBridgeFileTreeFilterCandidate.self,
                from: Data(invalidPayload.utf8)
            )
        }
    }
}
