import AppKit
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct GhosttyActionRouterTests {
    private final class FakeActionRoutingLookup: GhosttyActionRoutingLookup {
        private let surfaceIdsByViewObjectId: [ObjectIdentifier: UUID]
        private let paneIdsBySurfaceId: [UUID: UUID]

        init(
            surfaceIdsByViewObjectId: [ObjectIdentifier: UUID] = [:],
            paneIdsBySurfaceId: [UUID: UUID] = [:]
        ) {
            self.surfaceIdsByViewObjectId = surfaceIdsByViewObjectId
            self.paneIdsBySurfaceId = paneIdsBySurfaceId
        }

        func surfaceId(forViewObjectId viewObjectId: ObjectIdentifier) -> UUID? {
            surfaceIdsByViewObjectId[viewObjectId]
        }

        func paneId(for surfaceId: UUID) -> UUID? {
            paneIdsBySurfaceId[surfaceId]
        }
    }

    @Test(
        "routing with resolved surface object identifier returns false when surface is unknown"
    )
    func routeWithResolvedSurfaceView_unknownSurface() {
        let unknownSurfaceViewId = ObjectIdentifier(NSView(frame: .zero))
        let lookup = FakeActionRoutingLookup()

        let routed = Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue),
            payload: .noPayload,
            surfaceViewObjectId: unknownSurfaceViewId,
            routingLookup: lookup
        )

        #expect(!routed)
    }

    @Test("deferred tags are fully retired after explicit terminal event promotion")
    func deferredTags_areRetired() {
        #expect(Ghostty.ActionRouter.deferredTags.isEmpty)
        #expect(Ghostty.ActionRouter.interceptedTags.contains(.render))
    }

    @Test("Ghostty trace signal classes are pinned by semantic bucket")
    func traceSignalClassesArePinnedBySemanticBucket() {
        #expect(Ghostty.ActionRouter.signalClass(for: .desktopNotification) == .semantic)
        #expect(Ghostty.ActionRouter.signalClass(for: .commandFinished) == .semantic)
        #expect(Ghostty.ActionRouter.signalClass(for: .scrollbar) == .inferred)
        #expect(Ghostty.ActionRouter.signalClass(for: .setTitle) == .context)
        #expect(Ghostty.ActionRouter.signalClass(for: .newWindow) == .deferred)
        #expect(Ghostty.ActionRouter.signalClass(for: .render) == .deferred)
        #expect(
            Ghostty.ActionRouter.signalClass(for: .unhandled(tag: UInt32.max), fallbackActionTag: UInt32.max)
                == .unhandled)
    }

    @Test("Ghostty payload trace names use stable case names")
    func payloadTraceNamesUseStableCaseNames() {
        #expect(
            Ghostty.ActionRouter.payloadTraceName(
                .desktopNotification(title: "Build", body: "Complete")
            ) == "desktopNotification"
        )
        #expect(
            Ghostty.ActionRouter.payloadTraceName(.commandFinished(exitCode: 0, duration: 12))
                == "commandFinished"
        )
        #expect(
            Ghostty.ActionRouter.payloadTraceName(
                .openURL(url: "https://example.com/private/token", kindRawValue: 1)
            ) == "openURL"
        )
        #expect(Ghostty.ActionRouter.payloadTraceName(.noPayload) == "noPayload")
    }

    @Test("routing returns false when surface has no pane mapping")
    func routeWithResolvedSurfaceView_missingPaneMapping() {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId]
        )

        let routed = Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue),
            payload: .noPayload,
            surfaceViewObjectId: surfaceViewObjectId,
            routingLookup: lookup
        )

        #expect(!routed)
    }

    @Test("routing returns false when mapped pane id is not UUID v7")
    func routeWithResolvedSurfaceView_nonV7PaneId() {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: UUID()]
        )

        let routed = Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue),
            payload: .noPayload,
            surfaceViewObjectId: surfaceViewObjectId,
            routingLookup: lookup
        )

        #expect(!routed)
    }

    @Test("routing returns false when pane has no registered runtime")
    func routeWithResolvedSurfaceView_missingRuntime() {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        let runtimeRegistry = RuntimeRegistry()
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )

        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }

        let routed = Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue),
            payload: .noPayload,
            surfaceViewObjectId: surfaceViewObjectId,
            routingLookup: lookup
        )

        #expect(!routed)
    }

    @Test("registered surface reaches terminal runtime end to end")
    func actionRouter_endToEnd_registeredSurfaceReachesTerminalRuntime() {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                title: "Runtime"
            )
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )

        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }

        let routed = Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_SET_TITLE.rawValue),
            payload: .titleChanged("test"),
            surfaceViewObjectId: surfaceViewObjectId,
            routingLookup: lookup
        )

        #expect(routed)
        #expect(runtime.metadata.title == "test")
    }

    @Test("registered surface routes commandFinished payload through runtime envelope")
    func actionRouter_endToEnd_commandFinishedPayloadReachesRuntime() async {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                title: "Runtime"
            )
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )

        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }

        let routed = Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
            actionTag: UInt32(GHOSTTY_ACTION_COMMAND_FINISHED.rawValue),
            payload: .commandFinished(exitCode: 7, duration: 42),
            surfaceViewObjectId: surfaceViewObjectId,
            routingLookup: lookup
        )

        #expect(routed)

        let replay = await runtime.eventsSince(seq: 0)
        guard
            let firstEvent = replay.events.first,
            case .pane(let paneEnvelope) = firstEvent,
            case .terminal(.commandFinished(let exitCode, let duration)) = paneEnvelope.event
        else {
            Issue.record("Expected replay to include terminal commandFinished event")
            return
        }

        #expect(exitCode == 7)
        #expect(duration == 42)
    }

    @Test("registered surface routes observed terminal intelligence payloads through runtime envelopes")
    func actionRouter_endToEnd_observedTerminalIntelligencePayloadsReachRuntime() async {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                title: "Runtime"
            )
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )

        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
        }

        let routedDesktopNotification =
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_DESKTOP_NOTIFICATION.rawValue),
                payload: .desktopNotification(title: "Build", body: "Complete"),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        #expect(routedDesktopNotification)
        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_PROGRESS_REPORT.rawValue),
                payload: .progressReport(
                    stateRawValue: UInt32(GHOSTTY_PROGRESS_STATE_ERROR.rawValue),
                    progress: 80
                ),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_RENDERER_HEALTH.rawValue),
                payload: .rendererHealth(rawValue: UInt32(GHOSTTY_RENDERER_HEALTH_UNHEALTHY.rawValue)),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_SCROLLBAR.rawValue),
                payload: .scrollbar(total: 1000, offset: 900, length: 40),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_PWD.rawValue),
                payload: .cwdChanged("/tmp/project"),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )

        let replay = await runtime.eventsSince(seq: 0)
        let events = replay.events.compactMap { envelope -> PaneRuntimeEvent? in
            guard case .pane(let paneEnvelope) = envelope else { return nil }
            return paneEnvelope.event
        }

        #expect(
            events.contains {
                guard case .terminal(.progressReportUpdated(ProgressState(kind: .error, percent: 80))) = $0
                else { return false }
                return true
            }
        )
        #expect(
            events.contains {
                guard case .terminal(.rendererHealthChanged(false)) = $0 else { return false }
                return true
            }
        )
        #expect(
            events.contains {
                guard case .terminal(.scrollbarChanged) = $0 else { return false }
                return true
            } == false
        )
        #expect(
            events.contains {
                guard case .terminal(.cwdChanged("/tmp/project")) = $0 else { return false }
                return true
            }
        )
    }

    @Test("registered surface writes Ghostty action translation trace records")
    func actionRouterTrace_registeredSurfaceWritesTranslationRecord() async throws {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                title: "Runtime"
            )
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "ghostty-action-router",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.signal",
            ]),
            processIdentifier: 251,
            sessionID: "ghostty-session",
            timeUnixNano: { 909 }
        )

        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        Ghostty.ActionRouter.bindTraceRuntime(traceRuntime)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
            Ghostty.ActionRouter.bindTraceRuntime(nil)
        }

        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_DESKTOP_NOTIFICATION.rawValue),
                payload: .desktopNotification(title: "Build", body: "Complete"),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        await Ghostty.ActionRouter.drainTraceRuntimeForActionRouting()

        await Ghostty.ActionRouter.drainTraceRuntimeForActionRouting()
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"ghostty.action.translated\""))
        #expect(contents.contains("\"agentstudio.ghostty.action.name\":\"desktopNotification\""))
        #expect(contents.contains("\"agentstudio.ghostty.action.payload\":\"desktopNotification\""))
        #expect(contents.contains("\"agentstudio.ghostty.route.result\":true"))
        #expect(contents.contains("\"agentstudio.ghostty.signal.class\":\"semantic\""))
        #expect(contents.contains("\"agentstudio.pane.id\":\"\(paneUUID.uuidString)\""))
        #expect(contents.contains("\"agentstudio.runtime.event\":\"terminal.desktopNotificationRequested\""))
        #expect(contents.contains("\"agentstudio.surface.id\":\"\(surfaceId.uuidString)\""))
    }

    @Test("terminal activity tag alone does not write Ghostty action translation trace records")
    func actionRouterTrace_terminalActivityAloneDoesNotWriteTranslationRecord() async throws {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                title: "Runtime"
            )
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "ghostty-action-router-activity-only",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.activity",
            ]),
            processIdentifier: 253,
            sessionID: "ghostty-session",
            timeUnixNano: { 910 }
        )

        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        Ghostty.ActionRouter.bindTraceRuntime(traceRuntime)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
            Ghostty.ActionRouter.bindTraceRuntime(nil)
        }

        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_DESKTOP_NOTIFICATION.rawValue),
                payload: .desktopNotification(title: "Build", body: "Complete"),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        await Ghostty.ActionRouter.drainTraceRuntimeForActionRouting()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        #expect(FileManager.default.fileExists(atPath: outputFileURL.path) == false)
    }

    @Test("high-volume callbacks do not write per-callback Ghostty action trace records")
    func actionRouterTrace_highVolumeCallbacksDoNotWritePerCallbackRecords() async throws {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUID()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                title: "Runtime"
            )
        )
        let runtimeRegistry = RuntimeRegistry()
        _ = runtimeRegistry.register(runtime)
        let lookup = FakeActionRoutingLookup(
            surfaceIdsByViewObjectId: [surfaceViewObjectId: surfaceId],
            paneIdsBySurfaceId: [surfaceId: paneUUID]
        )
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "ghostty-action-router-scrollbar",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.signal",
            ]),
            processIdentifier: 254,
            sessionID: "ghostty-session",
            timeUnixNano: { 1001 }
        )

        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        Ghostty.ActionRouter.bindTraceRuntime(traceRuntime)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
            Ghostty.ActionRouter.bindTraceRuntime(nil)
        }

        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_SCROLLBAR.rawValue),
                payload: .scrollbar(total: 1000, offset: 900, length: 40),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: UInt32(GHOSTTY_ACTION_KEY_SEQUENCE.rawValue),
                payload: .keySequence(active: true, triggerTag: 0, key: 112, mods: 0),
                surfaceViewObjectId: surfaceViewObjectId,
                routingLookup: lookup
            )
        )
        await Task.yield()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        #expect(FileManager.default.fileExists(atPath: outputFileURL.path) == false)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-ghostty-action-router-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
