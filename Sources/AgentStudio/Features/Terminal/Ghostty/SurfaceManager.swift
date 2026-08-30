import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation
import GhosttyKit
import Observation
import os

private let logger = Logger(subsystem: "com.agentstudio", category: "SurfaceManager")

/// Manages Ghostty surface lifecycle independent of UI containers
/// Provides crash isolation, health monitoring, and undo support
@MainActor
@Observable
package final class SurfaceManager {
    package static let shared = SurfaceManager()

    package struct SurfaceCWDChangeEvent: Sendable {
        let surfaceId: UUID
        package let paneId: UUID?
        package let cwd: URL?
    }

    // MARK: - Published State

    /// Count of active surfaces (for observation)
    private(set) var activeSurfaceCount: Int = 0

    /// Count of hidden surfaces
    private(set) var hiddenSurfaceCount: Int = 0

    // MARK: - Delegates

    /// Health delegates (multiple supported via weak hash table)
    private var healthDelegates = NSHashTable<AnyObject>.weakObjects()

    weak var lifecycleDelegate: SurfaceLifecycleDelegate?

    /// Add a health delegate
    func addHealthDelegate(_ delegate: SurfaceHealthDelegate) {
        healthDelegates.add(delegate as AnyObject)
    }

    /// Remove a health delegate
    func removeHealthDelegate(_ delegate: SurfaceHealthDelegate) {
        healthDelegates.remove(delegate as AnyObject)
    }

    /// Notify all health delegates of a health change
    private func notifyHealthDelegates(_ surfaceId: UUID, healthChanged health: SurfaceHealth) {
        for delegate in healthDelegates.allObjects {
            (delegate as? SurfaceHealthDelegate)?.surface(surfaceId, healthChanged: health)
        }
    }

    /// Notify all health delegates of an error
    private func notifyHealthDelegatesError(_ surfaceId: UUID, error: SurfaceError) {
        for delegate in healthDelegates.allObjects {
            (delegate as? SurfaceHealthDelegate)?.surface(surfaceId, didEncounterError: error)
        }
    }

    // MARK: - Configuration

    /// How long to keep surfaces in undo stack (default 5 minutes)
    private let undoTTL: TimeInterval

    /// Maximum retry count for surface creation
    private let maxCreationRetries: Int

    /// Health check interval in seconds
    private let healthCheckInterval: TimeInterval

    /// Delay scheduler for time-dependent operations (e.g. undo expiration).
    private let delayScheduler: AsyncDelay
    private let now: @MainActor () -> Date
    let rendererStateDelivery: any SurfaceRendererStateDelivery

    // MARK: - Private State

    /// Surfaces attached to visible containers
    @ObservationIgnored var activeSurfaces: [UUID: ManagedSurface] = [:]

    /// Surfaces detached but kept alive (hidden terminals)
    @ObservationIgnored var hiddenSurfaces: [UUID: ManagedSurface] = [:]

    /// Recently closed surfaces for undo
    @ObservationIgnored private var undoStack: [SurfaceUndoEntry] = []

    /// Health state cache
    @ObservationIgnored private var surfaceHealth: [UUID: SurfaceHealth] = [:]

    /// Map from SurfaceView to UUID for notification handling
    @ObservationIgnored var surfaceViewToId: [ObjectIdentifier: UUID] = [:]

    @ObservationIgnored
    package var onAttachedBindingsChanged: (([UUID: UUID]) -> Void)?

    /// Async stream of live CWD updates from managed surfaces.
    private let cwdChangeContinuation: AsyncStream<SurfaceCWDChangeEvent>.Continuation
    private let cwdChangeStream: AsyncStream<SurfaceCWDChangeEvent>

    /// Health check timer
    private var healthCheckTimer: Timer?

    /// Checkpoint file URL
    private let checkpointURL: URL

    weak var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private var appCommandDispatcher: (any AppCommandDispatching)?

    // MARK: - Initialization

    package init(
        undoTTL: TimeInterval = 300,
        maxCreationRetries: Int = 2,
        healthCheckInterval: TimeInterval = 2.0,
        delayScheduler: AsyncDelay = .taskSleep,
        now: @escaping @MainActor () -> Date = Date.init,
        rendererStateDelivery: any SurfaceRendererStateDelivery = LiveSurfaceRendererStateDelivery.shared,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) {
        self.undoTTL = undoTTL
        self.maxCreationRetries = maxCreationRetries
        self.healthCheckInterval = healthCheckInterval
        self.delayScheduler = delayScheduler
        self.now = now
        self.rendererStateDelivery = rendererStateDelivery
        self.performanceTraceRecorder = performanceTraceRecorder
        (cwdChangeStream, cwdChangeContinuation) = AsyncStream.makeStream()

        let appSupport = AppDataPaths.rootDirectory()
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.checkpointURL = AppDataPaths.surfaceCheckpointURL()

        setupHealthMonitoring()

        logger.info("SurfaceManager initialized")
    }

    isolated deinit {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        cwdChangeContinuation.finish()
    }

    package var surfaceCWDChanges: AsyncStream<SurfaceCWDChangeEvent> {
        cwdChangeStream
    }

    package func setPerformanceTraceRecorder(_ recorder: AgentStudioPerformanceTraceRecorder?) {
        performanceTraceRecorder = recorder
    }

    package func setAppCommandDispatcher(_ dispatcher: any AppCommandDispatching) {
        appCommandDispatcher = dispatcher
    }

    // MARK: - Surface Creation

    /// Create a new surface with configuration
    /// - Parameters:
    ///   - config: Ghostty surface configuration
    ///   - metadata: Metadata to associate with the surface
    /// - Returns: Result with the managed surface or error
    package func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        guard let appCommandDispatcher else {
            preconditionFailure("SurfaceManager requires an App command dispatcher before creating surfaces")
        }

        RestoreTrace.log(
            "SurfaceManager.createSurface begin pane=\(metadata.paneId?.uuidString ?? "nil") title=\(metadata.title) cwd=\(metadata.cwd?.path ?? "nil") cmd=\(metadata.command ?? "nil")"
        )
        var mutableConfig = config

        // Allow delegate to modify config
        lifecycleDelegate?.surfaceWillCreate(config: &mutableConfig, metadata: metadata)

        // Attempt creation with retries
        for attempt in 0...maxCreationRetries {
            if attempt > 0 {
                logger.warning("Surface creation retry \(attempt)/\(self.maxCreationRetries)")
            }

            // Check if Ghostty is initialized (don't call .shared which fatalErrors)
            guard Ghostty.isInitialized else {
                logger.error("Ghostty app not initialized")
                if attempt == maxCreationRetries {
                    return .failure(.ghosttyNotInitialized)
                }
                continue
            }

            // Create surface view using Ghostty.App (not ghostty_app_t)
            let managedSurfaceID = UUIDv7.generate()
            let surfaceView = Ghostty.SurfaceView(
                app: Ghostty.shared,
                managedSurfaceID: managedSurfaceID,
                config: mutableConfig,
                appCommandDispatcher: appCommandDispatcher,
                performanceTraceRecorder: performanceTraceRecorder
            )

            // Verify surface was created successfully
            guard surfaceView.surface != nil else {
                logger.error("Surface creation returned nil surface")
                if attempt == maxCreationRetries {
                    return .failure(.creationFailed(retries: maxCreationRetries))
                }
                continue
            }

            switch acceptCreatedSurface(surfaceView, metadata: metadata) {
            case .success(let managed):
                RestoreTrace.log(
                    "SurfaceManager.createSurface success surface=\(managed.id) pane=\(metadata.paneId?.uuidString ?? "nil") frame=\(NSStringFromRect(surfaceView.frame))"
                )
                logger.info("Surface created: \(managed.id)")
                return .success(managed)
            case .failure(let error):
                logger.error("Surface creation could not establish initial renderer state")
                if attempt == maxCreationRetries {
                    return .failure(error)
                }
            }
        }

        RestoreTrace.log(
            "SurfaceManager.createSurface failed pane=\(metadata.paneId?.uuidString ?? "nil") retries=\(maxCreationRetries)"
        )
        return .failure(.creationFailed(retries: maxCreationRetries))
    }

    package func acceptCreatedSurface(
        _ surfaceView: Ghostty.SurfaceView,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        let surfaceID = surfaceView.managedSurfaceID
        guard managedSurface(for: surfaceID) == nil else {
            return .failure(.operationFailed("surface identity is already manager-owned"))
        }

        var managed = ManagedSurface(
            id: surfaceID,
            surface: surfaceView,
            metadata: metadata,
            state: .hidden
        )
        guard rendererStateDelivery.deliverVisibility(false, to: surfaceView) else {
            return .failure(.operationFailed("initial hidden renderer state delivery failed"))
        }
        _ = rendererStateDelivery.deliverFocus(false, to: surfaceView)
        managed.lastDeliveredVisibility = false

        surfaceView.focusRequester = self
        hiddenSurfaces[surfaceID] = managed
        surfaceHealth[surfaceID] = .healthy
        surfaceViewToId[ObjectIdentifier(surfaceView)] = surfaceID
        subscribeToSurfaceNotifications(surfaceView)
        updateCounts(recordLifecyclePopulation: false)
        if surfaceView.surface != nil {
            performanceTraceRecorder?.recordRendererCreated(
                surfaceID: surfaceID,
                active: activeSurfaces.count,
                hidden: hiddenSurfaces.count,
                closeUndo: undoStack.count
            )
            performanceTraceRecorder?.recordRendererVisibilityDelivery(
                surfaceID: surfaceID,
                visible: false,
                outcome: .applied
            )
        }
        lifecycleDelegate?.surfaceDidCreate(managed)
        return .success(managed)
    }

    // MARK: - Surface Attachment

    /// Attach a surface to a container (makes it visible/active)
    /// - Parameters:
    ///   - surfaceId: ID of the surface to attach
    ///   - paneId: ID of the pane to attach to
    /// - Returns: The surface view if successful
    @discardableResult
    package func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        RestoreTrace.log("SurfaceManager.attach requested surface=\(surfaceId) pane=\(paneId)")
        expireDueUndoEntries()
        let previousBindings = attachedBindings()
        // Check hidden surfaces first
        if var managed = hiddenSurfaces.removeValue(forKey: surfaceId) {
            managed.state = .active(paneId: paneId)
            managed.metadata.lastActiveAt = now()
            activeSurfaces[surfaceId] = managed

            updateCounts()
            notifyAttachedBindingsChanged(from: previousBindings)
            logger.info("Surface attached: \(surfaceId) to pane \(paneId)")
            RestoreTrace.log("SurfaceManager.attach fromHidden surface=\(surfaceId) pane=\(paneId)")
            return managed.surface
        }

        // Check undo stack
        if let idx = undoStack.firstIndex(where: { $0.surface.id == surfaceId }) {
            let entry = undoStack.remove(at: idx)
            entry.expirationTask?.cancel()

            var managed = entry.surface
            managed.state = .active(paneId: paneId)
            managed.metadata.lastActiveAt = now()
            activeSurfaces[surfaceId] = managed

            updateCounts()
            notifyAttachedBindingsChanged(from: previousBindings)
            logger.info("Surface restored from undo: \(surfaceId)")
            RestoreTrace.log("SurfaceManager.attach fromUndo surface=\(surfaceId) pane=\(paneId)")
            return managed.surface
        }

        // Check if already active (re-attach)
        if let managed = activeSurfaces[surfaceId] {
            var updated = managed
            updated.state = .active(paneId: paneId)
            updated.metadata.lastActiveAt = now()
            activeSurfaces[surfaceId] = updated
            notifyAttachedBindingsChanged(from: previousBindings)
            RestoreTrace.log("SurfaceManager.attach alreadyActive surface=\(surfaceId) pane=\(paneId)")
            return managed.surface
        }

        logger.warning("Surface not found for attach: \(surfaceId)")
        RestoreTrace.log("SurfaceManager.attach missing surface=\(surfaceId) pane=\(paneId)")
        return nil
    }

    /// Detach a surface from its container
    /// - Parameters:
    ///   - surfaceId: ID of the surface to detach
    ///   - reason: Why the surface is being detached
    package func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        guard activeSurfaces[surfaceId] != nil else {
            logger.warning("Surface not found for detach: \(surfaceId)")
            RestoreTrace.log("SurfaceManager.detach missing surface=\(surfaceId) reason=\(String(describing: reason))")
            return
        }
        RestoreTrace.log("SurfaceManager.detach begin surface=\(surfaceId) reason=\(String(describing: reason))")

        // Pause rendering
        _ = deliverVisibility(surfaceId, visible: false)

        let previousBindings = attachedBindings()
        guard var managed = activeSurfaces.removeValue(forKey: surfaceId) else {
            logger.error("Surface disappeared during synchronous detach: \(surfaceId)")
            return
        }

        let previousPaneAttachmentId: UUID?
        if case .active(let cid) = managed.state {
            previousPaneAttachmentId = cid
        } else {
            previousPaneAttachmentId = nil
        }

        switch reason {
        case .hide:
            managed.state = .hidden
            hiddenSurfaces[surfaceId] = managed
            logger.info("Surface hidden: \(surfaceId)")

        case .close:
            detachTerminalLocalActions(
                surfaceID: surfaceId,
                paneID: previousPaneAttachmentId
            )
            let closedAt = now()
            let expiresAt = closedAt.addingTimeInterval(undoTTL)
            managed.state = .pendingUndo(expiresAt: expiresAt)

            var entry = SurfaceUndoEntry(
                surface: managed,
                previousPaneAttachmentId: previousPaneAttachmentId,
                closedAt: closedAt,
                expiresAt: expiresAt
            )
            entry.expirationTask = scheduleUndoExpiration(surfaceId, at: expiresAt)
            undoStack.append(entry)
            logger.info("Surface closed (undo-able): \(surfaceId), expires at \(expiresAt)")

        case .move:
            // Temporarily detached for reattachment elsewhere
            managed.state = .hidden
            hiddenSurfaces[surfaceId] = managed
            logger.info("Surface detached for move: \(surfaceId)")
        }

        updateCounts()
        notifyAttachedBindingsChanged(from: previousBindings)
        RestoreTrace.log("SurfaceManager.detach end surface=\(surfaceId) reason=\(String(describing: reason))")
    }

    // MARK: - Surface Mobility

    /// Move a surface from one container to another
    func move(_ surfaceId: UUID, to targetPaneId: UUID) {
        let previousBindings = attachedBindings()
        guard var managed = activeSurfaces[surfaceId] ?? hiddenSurfaces.removeValue(forKey: surfaceId) else {
            logger.warning("Surface not found for move: \(surfaceId)")
            return
        }

        if case .active(let previousPaneID) = managed.state, previousPaneID != targetPaneId {
            detachTerminalLocalActions(surfaceID: surfaceId, paneID: previousPaneID)
        }

        managed.state = .active(paneId: targetPaneId)
        managed.metadata.lastActiveAt = now()
        activeSurfaces[surfaceId] = managed

        updateCounts()
        notifyAttachedBindingsChanged(from: previousBindings)

        logger.info("Surface moved: \(surfaceId) to \(targetPaneId)")
    }

    /// Swap two surfaces between containers
    func swap(_ surfaceA: UUID, with surfaceB: UUID) {
        let previousBindings = attachedBindings()
        guard var managedA = activeSurfaces[surfaceA],
            var managedB = activeSurfaces[surfaceB],
            case .active(let containerA) = managedA.state,
            case .active(let containerB) = managedB.state
        else {
            logger.warning("Cannot swap surfaces - not both active")
            return
        }

        managedA.state = .active(paneId: containerB)
        managedB.state = .active(paneId: containerA)

        activeSurfaces[surfaceA] = managedA
        activeSurfaces[surfaceB] = managedB
        notifyAttachedBindingsChanged(from: previousBindings)

        logger.info("Surfaces swapped: \(surfaceA) <-> \(surfaceB)")
    }

    // MARK: - Undo

    package func restoreClosedSurface(forPaneID paneID: UUID) -> ManagedSurface? {
        expireDueUndoEntries()
        guard
            let entryIndex = undoStack.lastIndex(where: {
                $0.previousPaneAttachmentId == paneID && $0.expiresAt > now()
            })
        else {
            logger.info("No eligible closed surface for pane: \(paneID)")
            return nil
        }

        let entry = undoStack.remove(at: entryIndex)
        entry.expirationTask?.cancel()

        var managed = entry.surface
        managed.state = .hidden
        managed.health = surfaceHealth[managed.id] ?? .healthy
        hiddenSurfaces[managed.id] = managed

        updateCounts()
        logger.info("Surface restored for pane: \(paneID), surface: \(managed.id)")
        return managed
    }

    /// Check if there are surfaces that can be restored
    var canUndo: Bool {
        expireDueUndoEntries()
        return !undoStack.isEmpty
    }

    // MARK: - Surface Destruction

    @discardableResult
    package func permanentlyRelease(
        _ surfaceId: UUID,
        reason: SurfacePermanentReleaseReason
    ) -> SurfacePermanentReleaseResult {
        let previousBindings = attachedBindings()
        detachTerminalLocalActions(surfaceID: surfaceId, paneID: paneId(for: surfaceId))
        let managed: ManagedSurface
        if activeSurfaces[surfaceId] != nil {
            _ = deliverVisibility(surfaceId, visible: false)
            guard let active = activeSurfaces.removeValue(forKey: surfaceId) else {
                return .notOwned
            }
            managed = active
        } else if let hidden = hiddenSurfaces.removeValue(forKey: surfaceId) {
            managed = hidden
        } else if let index = undoStack.firstIndex(where: { $0.surface.id == surfaceId }) {
            let entry = undoStack.remove(at: index)
            entry.expirationTask?.cancel()
            managed = entry.surface
        } else {
            return .notOwned
        }

        managed.surface.focusRequester = nil
        lifecycleDelegate?.surfaceWillDestroy(managed)
        surfaceViewToId.removeValue(forKey: ObjectIdentifier(managed.surface))
        surfaceHealth.removeValue(forKey: surfaceId)

        updateCounts(recordLifecyclePopulation: false)
        performanceTraceRecorder?.recordRendererPermanentlyReleased(
            surfaceID: surfaceId,
            reason: reason.rawValue,
            active: activeSurfaces.count,
            hidden: hiddenSurfaces.count,
            closeUndo: undoStack.count
        )
        notifyAttachedBindingsChanged(from: previousBindings)
        logger.info("Surface permanently released: \(surfaceId), reason: \(reason.rawValue)")
        return .released
    }

    @discardableResult
    package func permanentlyReleaseClosedSurface(
        forPaneID paneID: UUID,
        reason: SurfacePermanentReleaseReason
    ) -> SurfacePermanentReleaseResult {
        guard
            let surfaceID = undoStack.last(where: {
                $0.previousPaneAttachmentId == paneID
            })?.surface.id
        else {
            return .notOwned
        }
        return permanentlyRelease(surfaceID, reason: reason)
    }

    package func destroy(_ surfaceId: UUID) {
        _ = permanentlyRelease(surfaceId, reason: .explicitRemoval)
    }

    // MARK: - Surface Queries

    /// Get surface view by ID
    func surface(for id: UUID) -> Ghostty.SurfaceView? {
        activeSurfaces[id]?.surface ?? hiddenSurfaces[id]?.surface
    }

    /// Get managed surface by ID
    func managedSurface(for id: UUID) -> ManagedSurface? {
        activeSurfaces[id] ?? hiddenSurfaces[id]
    }

    /// Get metadata for a surface
    func metadata(for id: UUID) -> SurfaceMetadata? {
        activeSurfaces[id]?.metadata ?? hiddenSurfaces[id]?.metadata
    }

    /// Get health state for a surface
    func health(for id: UUID) -> SurfaceHealth {
        surfaceHealth[id] ?? .dead
    }

    /// Get current working directory for a surface
    func cwd(for id: UUID) -> URL? {
        metadata(for: id)?.cwd
    }

    /// Get all active surface IDs
    var activeSurfaceIds: [UUID] {
        Array(activeSurfaces.keys)
    }

    /// Get all hidden surface IDs
    var hiddenSurfaceIds: [UUID] {
        Array(hiddenSurfaces.keys)
    }

    /// Check if a process is running in the surface
    func isProcessRunning(_ surfaceId: UUID) -> Bool {
        guard let managed = activeSurfaces[surfaceId] ?? hiddenSurfaces[surfaceId],
            let surface = managed.surface.surface
        else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    /// Check if the process has exited
    func hasProcessExited(_ surfaceId: UUID) -> Bool {
        guard let managed = activeSurfaces[surfaceId] ?? hiddenSurfaces[surfaceId],
            let surface = managed.surface.surface
        else { return true }
        return ghostty_surface_process_exited(surface)
    }

    // MARK: - Safe Operation Wrapper

    /// Safe wrapper for surface operations - prevents crash propagation
    func withSurface<T>(
        _ id: UUID,
        operation: (ghostty_surface_t) -> T
    ) -> Result<T, SurfaceError> {
        guard let managed = activeSurfaces[id] ?? hiddenSurfaces[id] else {
            return .failure(.surfaceNotFound)
        }

        guard let surface = managed.surface.surface else {
            handleDeadSurface(id)
            return .failure(.surfaceDied)
        }

        let result = operation(surface)
        return .success(result)
    }

    // MARK: - Checkpoint Persistence

    /// Save checkpoint to disk
    func saveCheckpoint() {
        let allSurfaces = Array(activeSurfaces.values) + Array(hiddenSurfaces.values)
        let checkpoint = SurfaceCheckpoint(from: allSurfaces)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(checkpoint)
            try data.write(to: checkpointURL, options: .atomic)
            logger.info("Checkpoint saved: \(allSurfaces.count) surfaces")
        } catch {
            logger.error("Failed to save checkpoint: \(error)")
        }
    }

    /// Load checkpoint from disk
    func loadCheckpoint() -> SurfaceCheckpoint? {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: checkpointURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let checkpoint = try decoder.decode(SurfaceCheckpoint.self, from: data)
            logger.info("Checkpoint loaded: \(checkpoint.surfaces.count) surfaces")
            return checkpoint
        } catch {
            logger.error("Failed to load checkpoint: \(error)")
            return nil
        }
    }

    /// Clear checkpoint file
    func clearCheckpoint() {
        try? FileManager.default.removeItem(at: checkpointURL)
    }
}

extension SurfaceManager: TerminalSurfaceCommandDispatching {}
extension SurfaceManager: SurfaceFocusRequesting {}

// MARK: - Health Monitoring

extension SurfaceManager {

    private func setupHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(
            withTimeInterval: healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllSurfacesHealth()
            }
        }
    }

    private func subscribeToSurfaceNotifications(_ surfaceView: Ghostty.SurfaceView) {
        surfaceView.onRendererHealthChanged = { [weak self] surfaceViewId, isHealthy in
            self?.onRendererHealthChanged(
                surfaceViewId: surfaceViewId,
                isHealthyOverride: isHealthy
            )
        }
        surfaceView.onWorkingDirectoryChanged = { [weak self] surfaceViewId, rawPwd in
            self?.onWorkingDirectoryChanged(
                surfaceViewId: surfaceViewId,
                rawPwd: rawPwd
            )
        }
    }

    private func onRendererHealthChanged(
        surfaceViewId: ObjectIdentifier,
        isHealthyOverride: Bool?
    ) {
        guard let surfaceId = surfaceViewToId[surfaceViewId] else { return }

        let surfaceView = activeSurfaces[surfaceId]?.surface ?? hiddenSurfaces[surfaceId]?.surface
        guard let isHealthy = isHealthyOverride ?? surfaceView?.healthy else {
            let isActive = activeSurfaces[surfaceId] != nil
            logger.debug(
                "onRendererHealthChanged: no health value for surface \(surfaceId) active=\(isActive) viewNil=\(surfaceView == nil)"
            )
            return
        }

        if isHealthy {
            updateHealth(surfaceId, .healthy)
        } else {
            updateHealth(surfaceId, .unhealthy(reason: .rendererUnhealthy))
        }
    }

    private func onWorkingDirectoryChanged(
        surfaceViewId: ObjectIdentifier,
        rawPwd: String?
    ) {
        guard let surfaceId = surfaceViewToId[surfaceViewId] else { return }

        let url = CWDNormalizer.normalize(rawPwd)

        // Find the managed surface in either collection
        let (managed, isActive): (ManagedSurface?, Bool) = {
            if let m = activeSurfaces[surfaceId] { return (m, true) }
            if let m = hiddenSurfaces[surfaceId] { return (m, false) }
            return (nil, false)
        }()

        guard var current = managed else { return }
        guard current.metadata.cwd != url else { return }

        current.metadata.cwd = url
        if isActive {
            activeSurfaces[surfaceId] = current
        } else {
            hiddenSurfaces[surfaceId] = current
        }

        // Emit higher-level event for upstream consumers.
        cwdChangeContinuation.yield(
            SurfaceCWDChangeEvent(
                surfaceId: surfaceId,
                paneId: current.metadata.paneId,
                cwd: url
            )
        )

        logger.info("Surface \(surfaceId) CWD changed: \(url?.path ?? "nil")")
    }

    private func checkAllSurfacesHealth() {
        for (id, managed) in activeSurfaces {
            checkSurfaceHealth(id, managed)
        }
        for (id, managed) in hiddenSurfaces {
            checkSurfaceHealth(id, managed)
        }
    }

    private func checkSurfaceHealth(_ id: UUID, _ managed: ManagedSurface) {
        // Check if surface pointer is still valid
        guard let surface = managed.surface.surface else {
            updateHealth(id, .dead)
            return
        }

        // Check if process exited
        if ghostty_surface_process_exited(surface) {
            if case .processExited = surfaceHealth[id] {
                // Already in exited state
            } else {
                updateHealth(id, .processExited(exitCode: nil))
            }
            return
        }

        // Check renderer health via the surface view's published property
        if !managed.surface.healthy {
            updateHealth(id, .unhealthy(reason: .rendererUnhealthy))
            return
        }

        // Surface appears healthy
        if surfaceHealth[id] != .healthy {
            updateHealth(id, .healthy)
        }
    }

    private func updateHealth(_ id: UUID, _ health: SurfaceHealth) {
        let previousHealth = surfaceHealth[id]
        guard previousHealth != health else { return }

        surfaceHealth[id] = health

        // Update managed surface
        if var managed = activeSurfaces[id] {
            managed.health = health
            activeSurfaces[id] = managed
        } else if var managed = hiddenSurfaces[id] {
            managed.health = health
            hiddenSurfaces[id] = managed
        }

        notifyHealthDelegates(id, healthChanged: health)
        logger.info("Surface \(id) health changed: \(String(describing: health))")

        // Handle dead surfaces
        if case .dead = health {
            handleDeadSurface(id)
        }
    }

    private func handleDeadSurface(_ id: UUID) {
        logger.error("Surface died unexpectedly: \(id)")

        // Notify all delegates
        notifyHealthDelegatesError(id, error: .surfaceDied)

        // Don't remove from collections - let the UI handle it
        // The container can show error state and offer restart
    }

}

// MARK: - Undo Expiration

extension SurfaceManager {

    private func scheduleUndoExpiration(_ surfaceId: UUID, at date: Date) -> Task<Void, Never> {
        let delayScheduler = self.delayScheduler
        return Task { @MainActor [weak self, delayScheduler] in
            let delay = date.timeIntervalSince(self?.now() ?? date)
            if delay > 0 {
                try? await delayScheduler.wait(.seconds(delay))
            }

            guard !Task.isCancelled else { return }
            guard let self else { return }
            expireUndoEntry(surfaceId)
        }
    }

    private func expireUndoEntry(_ surfaceId: UUID) {
        guard undoStack.contains(where: { $0.surface.id == surfaceId && $0.expiresAt <= now() }) else { return }
        logger.info("Undo entry expired, destroying surface: \(surfaceId)")
        permanentlyRelease(surfaceId, reason: .undoExpired)
    }

    private func expireDueUndoEntries() {
        let currentTime = now()
        let dueSurfaceIDs = undoStack.compactMap { entry in
            entry.expiresAt <= currentTime ? entry.surface.id : nil
        }
        for surfaceID in dueSurfaceIDs {
            _ = permanentlyRelease(surfaceID, reason: .undoExpired)
        }
    }
}

// MARK: - Private Helpers

extension SurfaceManager {

    private func updateCounts(recordLifecyclePopulation: Bool = true) {
        activeSurfaceCount = activeSurfaces.count
        hiddenSurfaceCount = hiddenSurfaces.count
        if recordLifecyclePopulation {
            performanceTraceRecorder?.recordRendererManagerPopulation(
                active: activeSurfaces.count,
                hidden: hiddenSurfaces.count,
                closeUndo: undoStack.count
            )
        }
    }

    private func attachedBindings() -> [UUID: UUID] {
        activeSurfaces.reduce(into: [:]) { bindings, entry in
            guard case .active(let paneID) = entry.value.state else { return }
            bindings[entry.key] = paneID
        }
    }

    private func notifyAttachedBindingsChanged(from previousBindings: [UUID: UUID]) {
        let currentBindings = attachedBindings()
        guard currentBindings != previousBindings else { return }
        onAttachedBindingsChanged?(currentBindings)
    }

    /// Reverse-lookup: surfaceId → paneId.
    /// Derives from surface state (authoritative after attach/move) rather than
    /// metadata.paneId which is only set at creation time.
    func paneId(for surfaceId: UUID) -> UUID? {
        guard let managed = activeSurfaces[surfaceId] ?? hiddenSurfaces[surfaceId] else { return nil }
        if case .active(let paneId) = managed.state { return paneId }
        return managed.metadata.paneId
    }

    /// Reverse-lookup: SurfaceView → surfaceId via ObjectIdentifier map.
    func surfaceId(forView surfaceView: Ghostty.SurfaceView) -> UUID? {
        surfaceId(forViewObjectId: ObjectIdentifier(surfaceView))
    }

    /// Reverse-lookup: SurfaceView ObjectIdentifier → surfaceId.
    func surfaceId(forViewObjectId viewObjectId: ObjectIdentifier) -> UUID? {
        surfaceViewToId[viewObjectId]
    }

    /// Reverse-lookup: paneId → surfaceId.
    func surfaceId(forPaneId paneId: UUID) -> UUID? {
        if let activeMatch = activeSurfaces.first(where: { _, managed in
            if case .active(let activePaneId) = managed.state {
                return activePaneId == paneId
            }
            return managed.metadata.paneId == paneId
        }) {
            return activeMatch.key
        }

        if let hiddenMatch = hiddenSurfaces.first(where: { _, managed in
            managed.metadata.paneId == paneId
        }) {
            return hiddenMatch.key
        }

        return nil
    }
}

// MARK: - Debug/Testing

#if DEBUG
    extension SurfaceManager {
        /// Test crash isolation - use in development only
        func testCrash(_ surfaceId: UUID, thread: CrashThread) {
            _ = withSurface(surfaceId) { surface in
                let action: String
                switch thread {
                case .main: action = "crash:main"
                case .io: action = "crash:io"
                case .render: action = "crash:render"
                }

                action.withCString { ptr in
                    _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
                }
            }
        }

        enum CrashThread {
            case main  // Will crash entire app
            case io  // Should be isolated
            case render  // Should be isolated
        }

        /// Debug: Print all surface states
        func debugPrintState() {
            print("=== SurfaceManager State ===")
            print("Active: \(activeSurfaces.count)")
            for (id, managed) in activeSurfaces {
                print("  - \(id): \(managed.metadata.title), health: \(surfaceHealth[id] ?? .dead)")
            }
            print("Hidden: \(hiddenSurfaces.count)")
            for (id, managed) in hiddenSurfaces {
                print("  - \(id): \(managed.metadata.title), health: \(surfaceHealth[id] ?? .dead)")
            }
            print("Undo stack: \(undoStack.count)")
            for entry in undoStack {
                print("  - \(entry.surface.id): expires \(entry.expiresAt)")
            }
        }
    }
#endif
