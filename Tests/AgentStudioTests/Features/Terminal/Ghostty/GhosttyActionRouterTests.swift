import AgentStudioAppIPC
import AgentStudioProgrammaticControl
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

    @Test("contracted tab title retains its runtime event kind and replay route")
    func contractedTabTitleRetainsRuntimeRoute() async throws {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(paneId: paneId, title: "Before")
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

        Ghostty.ActionRouter.routeContractedTitleMetadata(
            .tabTitleChanged("After"),
            surfaceViewObjectID: surfaceViewObjectId,
            routingLookup: lookup
        )

        #expect(runtime.metadata.title == "After")
        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.count == 1)
        let envelope = try #require(replay.events.first)
        guard case .pane(let paneEnvelope) = envelope else {
            Issue.record("expected pane runtime envelope")
            return
        }
        guard case .terminal(.tabTitleChanged(let title)) = paneEnvelope.event else {
            Issue.record("expected contracted tab-title runtime event")
            return
        }
        #expect(title == "After")
    }

    @Test("equal contracted first title still records startup readiness")
    func equalContractedFirstTitleRecordsStartupReadiness() async throws {
        let surfaceViewObjectId = ObjectIdentifier(NSView(frame: .zero))
        let surfaceId = UUIDv7.generate()
        let paneUUID = UUIDv7.generate()
        let paneId = PaneId(existingUUID: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(paneId: paneId, title: "Same")
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
                "AGENTSTUDIO_TRACE_NAME": "equal-title-startup",
                "AGENTSTUDIO_TRACE_TAGS": "terminal.startup",
            ]),
            processIdentifier: 255,
            sessionID: "equal-title-startup",
            timeUnixNano: { 910 }
        )
        let startupRecorder = AgentStudioStartupTraceRecorder(traceRuntime: traceRuntime)
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(runtimeRegistry)
        Ghostty.ActionRouter.bindStartupTraceRecorder(startupRecorder)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
            Ghostty.ActionRouter.bindStartupTraceRecorder(nil)
        }

        Ghostty.ActionRouter.routeContractedTitleMetadata(
            .titleChanged("Same"),
            surfaceViewObjectID: surfaceViewObjectId,
            routingLookup: lookup
        )
        try await startupRecorder.drain()

        #expect((await runtime.eventsSince(seq: 0)).events.isEmpty)
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("terminal.startup.title_ready"))
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

    @Test(
        "translated admission isolates mixed local pressure while exact facts retain every publication path"
    )
    func translatedAdmission_mixedLocalPressureIsolatedFromExactFacts() async throws {
        let localSampleCount = 100_000
        let exactFactCount = 25
        let fixture = await MixedAdmissionFixture(exactFactCapacity: exactFactCount)
        let originalRegistry = Ghostty.ActionRouter.runtimeRegistryForActionRouting
        Ghostty.ActionRouter.setRuntimeRegistry(fixture.runtimeRegistry)
        defer {
            Ghostty.ActionRouter.setRuntimeRegistry(originalRegistry)
            fixture.accumulator.removeSurface(fixture.surfaceID)
        }

        try routeMixedTerminalPressure(
            fixture: fixture,
            localSampleCount: localSampleCount,
            exactFactCount: exactFactCount
        )
        try assertMixedPressureAccumulatorConverges(fixture: fixture, localSampleCount: localSampleCount)
        try await assertMixedPressurePublicationPaths(fixture: fixture, exactFactCount: exactFactCount)
        await fixture.shutdown()
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

    private func commandFinishedFacts(from envelopes: [RuntimeEnvelope]) -> [CommandFinishedFact] {
        envelopes.compactMap { envelope in
            guard case .pane(let paneEnvelope) = envelope,
                case .terminal(.commandFinished(let exitCode, let duration)) = paneEnvelope.event
            else { return nil }
            return CommandFinishedFact(exitCode: exitCode, duration: duration)
        }
    }

    private func expectedCommandFinishedFacts(count: Int) -> [CommandFinishedFact] {
        (0..<count).map { CommandFinishedFact(exitCode: $0, duration: UInt64($0 + 1)) }
    }

    private func routeMixedTerminalPressure(
        fixture: MixedAdmissionFixture,
        localSampleCount: Int,
        exactFactCount: Int
    ) throws {
        let localSamplesPerExactFact = localSampleCount / exactFactCount
        for factIndex in 0..<exactFactCount {
            for localOffset in 0..<localSamplesPerExactFact {
                let sampleIndex = factIndex * localSamplesPerExactFact + localOffset
                routeLocalTranslatedSample(sampleIndex, fixture: fixture)
            }

            let ipcSnapshotBeforeExactFact = try fixture.ipcAdapter.terminalSnapshot(fixture.paneHandle)
            #expect(ipcSnapshotBeforeExactFact.lastSequence == UInt64(factIndex))
            routeExactCommandFinishedFact(factIndex, fixture: fixture)
        }
    }

    private func routeLocalTranslatedSample(_ sampleIndex: Int, fixture: MixedAdmissionFixture) {
        let localAction = localTranslatedAction(sampleIndex: sampleIndex)
        let translatedEvent = GhosttyAdapter.shared.translate(
            actionTag: UInt32(localAction.tag.rawValue),
            payload: localAction.payload
        )
        let disposition = Ghostty.ActionRouter.admitTranslatedActionToTerminalRuntime(
            translatedEvent,
            surfaceID: fixture.surfaceID,
            accumulator: fixture.accumulator
        )
        #expect(disposition == .handledLocally)
    }

    private func localTranslatedAction(
        sampleIndex: Int
    ) -> (tag: GhosttyActionTag, payload: GhosttyAdapter.ActionPayload) {
        switch sampleIndex % 7 {
        case 0:
            return (.mouseShape, .mouseShape(rawValue: UInt32(GHOSTTY_MOUSE_SHAPE_TEXT.rawValue)))
        case 1:
            return (.mouseVisibility, .mouseVisibility(rawValue: UInt32(GHOSTTY_MOUSE_VISIBLE.rawValue)))
        case 2:
            return (
                .scrollbar,
                .scrollbar(
                    total: UInt64(sampleIndex + 100),
                    offset: UInt64(sampleIndex + 80),
                    length: 20
                )
            )
        case 3:
            return (.startSearch, .startSearch("query-\(sampleIndex)"))
        case 4:
            return (.searchTotal, .searchTotal(sampleIndex))
        case 5:
            return (.searchSelected, .searchSelected(sampleIndex))
        default:
            return (.endSearch, .endSearch)
        }
    }

    private func routeExactCommandFinishedFact(_ factIndex: Int, fixture: MixedAdmissionFixture) {
        let exactPayload = GhosttyAdapter.ActionPayload.commandFinished(
            exitCode: factIndex,
            duration: UInt64(factIndex + 1)
        )
        let exactActionTag = UInt32(GHOSTTY_ACTION_COMMAND_FINISHED.rawValue)
        let translatedEvent = GhosttyAdapter.shared.translate(
            actionTag: exactActionTag,
            payload: exactPayload
        )
        let disposition = Ghostty.ActionRouter.admitTranslatedActionToTerminalRuntime(
            translatedEvent,
            surfaceID: fixture.surfaceID,
            accumulator: fixture.accumulator
        )

        #expect(disposition == .routeExactFactOrControl)
        #expect(
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor(
                actionTag: exactActionTag,
                payload: exactPayload,
                surfaceViewObjectId: fixture.surfaceViewObjectID,
                routingLookup: fixture.routingLookup
            )
        )
    }

    private func assertMixedPressureAccumulatorConverges(
        fixture: MixedAdmissionFixture,
        localSampleCount: Int
    ) throws {
        #expect(fixture.drainScheduleRecorder.scheduledSurfaceIDs == [fixture.surfaceID])
        #expect(fixture.accumulator.pendingSurfaceCount == 1)
        #expect(
            fixture.accumulator.retainedEntryCount
                <= TerminalLocalActionAccumulator.maximumRetainedEntriesPerSurface
        )

        let localBatch = try #require(fixture.accumulator.beginDrain(for: fixture.surfaceID))
        #expect(localBatch.metrics.offeredCount == UInt64(localSampleCount))
        #expect(fixture.accumulator.finishDrain(for: fixture.surfaceID) == .idle)
        #expect(fixture.accumulator.pendingSurfaceCount == 0)
        #expect(fixture.accumulator.retainedEntryCount == 0)
    }

    private func assertMixedPressurePublicationPaths(
        fixture: MixedAdmissionFixture,
        exactFactCount: Int
    ) async throws {
        let replay = await fixture.runtime.eventsSince(seq: 0)
        let replayFacts = commandFinishedFacts(from: replay.events)
        #expect(replayFacts == expectedCommandFinishedFacts(count: exactFactCount))

        await assertEventuallyAsync("runtime and EventBus subscribers should receive every exact fact") {
            let runtimeEventCount = await fixture.runtimeSubscriber.snapshot().count
            let eventBusEventCount = await fixture.eventBusSubscriber.snapshot().count
            return runtimeEventCount == exactFactCount && eventBusEventCount == exactFactCount
        }
        #expect(commandFinishedFacts(from: await fixture.runtimeSubscriber.snapshot()) == replayFacts)
        #expect(commandFinishedFacts(from: await fixture.eventBusSubscriber.snapshot()) == replayFacts)

        let eventBusDiagnostics = await fixture.eventBusHarness.bus.diagnosticsSnapshot()
        let deliveryDiagnostics = try #require(
            eventBusDiagnostics.activeSubscribers.first { $0.subscriberName == "mixedTerminalAdmission" }
        )
        #expect(deliveryDiagnostics.yieldedCount == UInt64(exactFactCount))
        #expect(deliveryDiagnostics.consumedCount == UInt64(exactFactCount))
        #expect(deliveryDiagnostics.pendingDeliveryCount == 0)
        #expect(deliveryDiagnostics.liveDroppedCount == 0)
        #expect(deliveryDiagnostics.replayDroppedCount == 0)

        let finalIPCSnapshot = try fixture.ipcAdapter.terminalSnapshot(fixture.paneHandle)
        #expect(finalIPCSnapshot.lastSequence == UInt64(exactFactCount))
        let ipcWaitResult = try await fixture.ipcAdapter.waitForTerminal(
            fixture.paneHandle,
            condition: .commandFinished,
            timeout: .milliseconds(1),
            afterSequence: 0
        )
        #expect(ipcWaitResult.eventName == .terminalCommandFinished)
        #expect(ipcWaitResult.exitCode == 0)
        #expect(ipcWaitResult.duration == 1)
    }

    @MainActor
    private struct MixedAdmissionFixture {
        let surfaceViewObjectID: ObjectIdentifier
        let surfaceID: UUID
        let pane: Pane
        let eventBusHarness: EventBusHarness<RuntimeEnvelope>
        let eventBusSubscriber: RecordingSubscriber<RuntimeEnvelope>
        let runtime: TerminalRuntime
        let runtimeSubscriber: RecordingSubscriber<RuntimeEnvelope>
        let runtimeRegistry: RuntimeRegistry
        let routingLookup: FakeActionRoutingLookup
        let ipcAdapter: AgentStudioIPCRuntimeAdapter
        let drainScheduleRecorder: MixedAdmissionDrainScheduleRecorder
        let accumulator: TerminalLocalActionAccumulator

        var paneHandle: IPCHandle {
            IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id))
        }

        init(exactFactCapacity: Int) async {
            let surfaceViewObjectID = ObjectIdentifier(NSView(frame: .zero))
            let surfaceID = UUIDv7.generate()
            let workspaceStore = WorkspaceStore()
            let pane = workspaceStore.createPane(
                content: .terminal(
                    TerminalState(provider: .zmx, lifetime: .temporary, zmxSessionID: .generateUUIDv7())
                ),
                metadata: PaneMetadata(title: "Mixed admission")
            )
            workspaceStore.appendTab(Tab(paneId: pane.id))
            workspaceStore.setActiveTab(workspaceStore.tabs[0].id)

            let paneID = PaneId(existingUUID: pane.id)
            let eventBusHarness = EventBusHarness<RuntimeEnvelope>()
            let eventBusSubscriber = await eventBusHarness.makeSubscriber(
                policy: .criticalUnbounded,
                subscriberName: "mixedTerminalAdmission"
            )
            let runtime = TerminalRuntime(
                paneId: paneID,
                metadata: PaneMetadata(paneId: paneID, contentType: .terminal, title: "Mixed admission"),
                replayBuffer: EventReplayBuffer(capacity: exactFactCapacity),
                paneEventBus: eventBusHarness.bus
            )
            let runtimeSubscriber = RecordingSubscriber(stream: runtime.subscribe())
            let runtimeRegistry = RuntimeRegistry()
            _ = runtimeRegistry.register(runtime)
            let routingLookup = FakeActionRoutingLookup(
                surfaceIdsByViewObjectId: [surfaceViewObjectID: surfaceID],
                paneIdsBySurfaceId: [surfaceID: pane.id]
            )
            let ipcAdapter = AgentStudioIPCRuntimeAdapter(
                workspaceStore: workspaceStore,
                runtimeRegistry: runtimeRegistry,
                commandDispatcher: SuccessfulRuntimeCommandDispatcher(),
                eventBus: eventBusHarness.bus
            )
            let drainScheduleRecorder = MixedAdmissionDrainScheduleRecorder()
            let accumulator = TerminalLocalActionAccumulator(scheduleDrain: drainScheduleRecorder.record)

            self.surfaceViewObjectID = surfaceViewObjectID
            self.surfaceID = surfaceID
            self.pane = pane
            self.eventBusHarness = eventBusHarness
            self.eventBusSubscriber = eventBusSubscriber
            self.runtime = runtime
            self.runtimeSubscriber = runtimeSubscriber
            self.runtimeRegistry = runtimeRegistry
            self.routingLookup = routingLookup
            self.ipcAdapter = ipcAdapter
            self.drainScheduleRecorder = drainScheduleRecorder
            self.accumulator = accumulator
        }

        func shutdown() async {
            await runtimeSubscriber.shutdown()
            await eventBusSubscriber.shutdown()
            _ = await runtime.shutdown(timeout: .zero)
            await assertBusDrained(eventBusHarness.bus)
        }
    }
}

private struct CommandFinishedFact: Equatable {
    let exitCode: Int
    let duration: UInt64
}

@MainActor
private struct SuccessfulRuntimeCommandDispatcher: PaneRuntimeCommandDispatching {
    func dispatchRuntimeCommand(
        _ command: PaneRuntimeCommand,
        target: RuntimeCommandTarget,
        correlationId: UUID?
    ) async -> ActionResult {
        .success(commandId: UUIDv7.generate())
    }
}

private final class MixedAdmissionDrainScheduleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID] = []

    var scheduledSurfaceIDs: [UUID] {
        lock.withLock { storage }
    }

    func record(_ surfaceID: UUID, _: TerminalLocalDrainSchedule) {
        lock.withLock {
            storage.append(surfaceID)
        }
    }
}
