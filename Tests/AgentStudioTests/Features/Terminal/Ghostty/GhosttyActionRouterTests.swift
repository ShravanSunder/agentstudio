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

    @Test("deferred tags capture high-frequency and feature-gated actions explicitly")
    func deferredTags_coverVisualAndFeatureGatedActions() {
        #expect(
            Ghostty.ActionRouter.deferredTags.contains(.render)
        )
        #expect(
            Ghostty.ActionRouter.deferredTags.contains(.mouseShape)
        )
        #expect(
            Ghostty.ActionRouter.deferredTags.contains(.setTabTitle)
        )
        #expect(
            Ghostty.ActionRouter.deferredTags.contains(.startSearch)
        )
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
        let paneId = PaneId(uuid: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                source: .init(TerminalSource.floating(launchDirectory: nil, title: "Runtime")),
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
        let paneId = PaneId(uuid: paneUUID)
        let runtime = TerminalRuntime(
            paneId: paneId,
            metadata: PaneMetadata(
                paneId: paneId,
                source: .init(TerminalSource.floating(launchDirectory: nil, title: "Runtime")),
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
}
