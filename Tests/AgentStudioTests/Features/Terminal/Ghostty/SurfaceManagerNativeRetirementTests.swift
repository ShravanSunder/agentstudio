import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("Surface manager native retirement", .serialized)
struct SurfaceManagerNativeRetirementTests {
    @Test("every active hidden and undo attachment protects its zmx session")
    func allNativeOwnersProtectTheSession() throws {
        let manager = SurfaceManager(maxCreationRetries: 0, healthCheckInterval: 3600)
        let sessionID = ZmxSessionID.generateUUIDv7()
        let firstPaneID = UUIDv7.generate()
        let secondPaneID = UUIDv7.generate()
        let first = Ghostty.SurfaceView(
            managedSurfaceID: UUIDv7.generate(), appCommandDispatcher: RetirementNoOpAppCommandDispatcher())
        let second = Ghostty.SurfaceView(
            managedSurfaceID: UUIDv7.generate(), appCommandDispatcher: RetirementNoOpAppCommandDispatcher())
        let firstManaged = try manager.acceptCreatedSurface(
            first, metadata: SurfaceMetadata(paneId: firstPaneID, zmxSessionID: sessionID)
        ).get()
        #expect(manager.hasNativeAttachments(for: sessionID))
        manager.attach(firstManaged.id, to: firstPaneID)
        #expect(manager.hasNativeAttachments(for: sessionID))
        manager.retainSurfacesForUndo(forPaneIDs: [firstPaneID])
        #expect(manager.hasNativeAttachments(for: sessionID))
        let secondManaged = try manager.acceptCreatedSurface(
            second, metadata: SurfaceMetadata(paneId: secondPaneID, zmxSessionID: sessionID)
        ).get()
        manager.releaseUndoSurfaces(forPaneIDs: [firstPaneID])
        #expect(manager.hasNativeAttachments(for: sessionID))
        manager.destroy(secondManaged.id)
        #expect(!manager.hasNativeAttachments(for: sessionID))
        #expect(!manager.hasNativeAttachments(for: .generateUUIDv7()))
    }

    @Test("undo expiry retires the native instance even while its view is retained")
    func retainedViewDoesNotDelayNativeRetirement() throws {
        var retiredSurfaceIDs: [UUID] = []
        let manager = SurfaceManager(
            maxCreationRetries: 0,
            healthCheckInterval: 3600,
            nativeSurfaceRetirement: { retiredSurfaceIDs.append($0.managedSurfaceID) })
        let paneID = UUIDv7.generate()
        let surface = Ghostty.SurfaceView(
            managedSurfaceID: UUIDv7.generate(), appCommandDispatcher: RetirementNoOpAppCommandDispatcher())
        let managed = try manager.acceptCreatedSurface(surface, metadata: SurfaceMetadata(paneId: paneID)).get()
        manager.attach(managed.id, to: paneID)
        manager.retainSurfacesForUndo(forPaneIDs: [paneID])
        #expect(retiredSurfaceIDs.isEmpty)

        manager.releaseUndoSurfaces(forPaneIDs: [paneID])

        #expect(retiredSurfaceIDs == [surface.managedSurfaceID])
        #expect(manager.canUndo == false)
        #expect(manager.surface(for: managed.id) == nil)
        // A second cleanup request cannot retire the same instance twice.
        manager.destroy(managed.id)
        #expect(retiredSurfaceIDs == [surface.managedSurfaceID])
        // The strong local deliberately survives every retirement assertion.
        withExtendedLifetime(surface) {}
    }
}

@MainActor
private final class RetirementNoOpAppCommandDispatcher: AppCommandDispatching {
    func dispatch(_: AppCommand) {}
    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}
    func canDispatch(_: AppCommand) -> Bool { false }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}
