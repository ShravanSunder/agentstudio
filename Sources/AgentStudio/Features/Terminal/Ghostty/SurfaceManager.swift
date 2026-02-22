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
final class SurfaceManager {
    static let shared = SurfaceManager()

    struct SurfaceCWDChangeEvent: Sendable {
        let surfaceId: UUID
        let paneId: UUID?
        let cwd: URL?
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

    /// Clock for scheduling time-dependent operations (e.g. undo expiration).
    private let clock: any Clock<Duration>

    // MARK: - Private State

    /// Surfaces attached to visible containers
    private var activeSurfaces: [UUID: ManagedSurface] = [:]

    /// Surfaces detached but kept alive (hidden terminals)
    private var hiddenSurfaces: [UUID: ManagedSurface] = [:]

    /// Recently closed surfaces for undo
    private var undoStack: [SurfaceUndoEntry] = []

    /// Health state cache
    private var surfaceHealth: [UUID: SurfaceHealth] = [:]

    /// Map from SurfaceView to UUID for notification handling
    private var surfaceViewToId: [ObjectIdentifier: UUID] = [:]

    /// Async stream of live CWD updates from managed surfaces.
    private let cwdChangeContinuation: AsyncStream<SurfaceCWDChangeEvent>.Continuation
    private let cwdChangeStream: AsyncStream<SurfaceCWDChangeEvent>

    /// Health check timer
    private var healthCheckTimer: Timer?

    /// Checkpoint file URL
    private let checkpointURL: URL
    private var ghosttyNotificationObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    private init(
        undoTTL: TimeInterval = 300,
        maxCreationRetries: Int = 2,
        healthCheckInterval: TimeInterval = 2.0,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.undoTTL = undoTTL
        self.maxCreationRetries = maxCreationRetries
        self.healthCheckInterval = healthCheckInterval
        self.clock = clock
        (cwdChangeStream, cwdChangeContinuation) = AsyncStream.makeStream()

        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.checkpointURL = appSupport.appending(path: "surface-checkpoint.json")

        setupHealthMonitoring()
        subscribeToGhosttyNotifications()

        logger.info("SurfaceManager initialized")
    }

    isolated deinit {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        cwdChangeContinuation.finish()
        for observer in ghosttyNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        ghosttyNotificationObservers.removeAll()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceCWDChangeEvent> {
        cwdChangeStream
    }

    // MARK: - Surface Creation

    /// Create a new surface with configuration
    /// - Parameters:
    ///   - config: Ghostty surface configuration
    ///   - metadata: Metadata to associate with the surface
    /// - Returns: Result with the managed surface or error
    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {

        RestoreTrace.log(
            "SurfaceManager.createSurface begin pane=\(metadata.paneId?.uuidString ?? "nil") title=\(metadata.title) cwd=\(metadata.workingDirectory?.path ?? "nil") cmd=\(metadata.command ?? "nil")"
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
            let surfaceView = Ghostty.SurfaceView(app: Ghostty.shared, config: mutableConfig)

            // Verify surface was created successfully
            guard surfaceView.surface != nil else {
                logger.error("Surface creation returned nil surface")
                if attempt == maxCreationRetries {
                    return .failure(.creationFailed(retries: maxCreationRetries))
                }
                continue
            }

            // Success - create managed surface
            let managed = ManagedSurface(
                surface: surfaceView,
                metadata: metadata,
                state: .hidden
            )

            // Register in collections
            hiddenSurfaces[managed.id] = managed
            surfaceHealth[managed.id] = .healthy
            surfaceViewToId[ObjectIdentifier(surfaceView)] = managed.id
            RestoreTrace.log(
                "SurfaceManager.createSurface success surface=\(managed.id) pane=\(metadata.paneId?.uuidString ?? "nil") frame=\(NSStringFromRect(surfaceView.frame))"
            )

            // Subscribe to this surface's notifications
            subscribeToSurfaceNotifications(surfaceView)

            // Update counts
            updateCounts()

            // Notify delegate
            lifecycleDelegate?.surfaceDidCreate(managed)

            logger.info("Surface created: \(managed.id)")
            return .success(managed)
        }

        RestoreTrace.log(
            "SurfaceManager.createSurface failed pane=\(metadata.paneId?.uuidString ?? "nil") retries=\(maxCreationRetries)"
        )
        return .failure(.creationFailed(retries: maxCreationRetries))
    }

    // MARK: - Surface Attachment

    /// Attach a surface to a container (makes it visible/active)
    /// - Parameters:
    ///   - surfaceId: ID of the surface to attach
    ///   - paneId: ID of the pane to attach to
    /// - Returns: The surface view if successful
    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        RestoreTrace.log("SurfaceManager.attach requested surface=\(surfaceId) pane=\(paneId)")
        // Check hidden surfaces first
        if var managed = hiddenSurfaces.removeValue(forKey: surfaceId) {
            managed.state = .active(paneId: paneId)
            managed.metadata.lastActiveAt = Date()
            activeSurfaces[surfaceId] = managed

            // Resume rendering
            setOcclusion(surfaceId, visible: true)

            updateCounts()
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
            managed.metadata.lastActiveAt = Date()
            activeSurfaces[surfaceId] = managed

            setOcclusion(surfaceId, visible: true)

            updateCounts()
            logger.info("Surface restored from undo: \(surfaceId)")
            RestoreTrace.log("SurfaceManager.attach fromUndo surface=\(surfaceId) pane=\(paneId)")
            return managed.surface
        }

        // Check if already active (re-attach)
        if let managed = activeSurfaces[surfaceId] {
            var updated = managed
            updated.state = .active(paneId: paneId)
            updated.metadata.lastActiveAt = Date()
            activeSurfaces[surfaceId] = updated
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
    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        guard var managed = activeSurfaces.removeValue(forKey: surfaceId) else {
            logger.warning("Surface not found for detach: \(surfaceId)")
            RestoreTrace.log("SurfaceManager.detach missing surface=\(surfaceId) reason=\(String(describing: reason))")
            return
        }
        RestoreTrace.log("SurfaceManager.detach begin surface=\(surfaceId) reason=\(String(describing: reason))")

        // Pause rendering
        setOcclusion(surfaceId, visible: false)

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
            let expiresAt = Date().addingTimeInterval(undoTTL)
            managed.state = .pendingUndo(expiresAt: expiresAt)

            var entry = SurfaceUndoEntry(
                surface: managed,
                previousPaneAttachmentId: previousPaneAttachmentId,
                closedAt: Date(),
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
        RestoreTrace.log("SurfaceManager.detach end surface=\(surfaceId) reason=\(String(describing: reason))")
    }

    // MARK: - Surface Mobility

    /// Move a surface from one container to another
    func move(_ surfaceId: UUID, to targetPaneId: UUID) {
        guard var managed = activeSurfaces[surfaceId] ?? hiddenSurfaces.removeValue(forKey: surfaceId) else {
            logger.warning("Surface not found for move: \(surfaceId)")
            return
        }

        managed.state = .active(paneId: targetPaneId)
        managed.metadata.lastActiveAt = Date()
        activeSurfaces[surfaceId] = managed

        setOcclusion(surfaceId, visible: true)
        updateCounts()

        logger.info("Surface moved: \(surfaceId) to \(targetPaneId)")
    }

    /// Swap two surfaces between containers
    func swap(_ surfaceA: UUID, with surfaceB: UUID) {
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

        logger.info("Surfaces swapped: \(surfaceA) <-> \(surfaceB)")
    }

    // MARK: - Undo

    /// Restore the most recently closed surface
    /// - Returns: The restored surface if available
    func undoClose() -> ManagedSurface? {
        guard let entry = undoStack.popLast() else {
            logger.info("Nothing to undo")
            return nil
        }

        entry.expirationTask?.cancel()

        var managed = entry.surface
        managed.state = .hidden
        managed.health = surfaceHealth[managed.id] ?? .healthy
        hiddenSurfaces[managed.id] = managed

        updateCounts()
        logger.info("Surface undo: \(managed.id)")
        return managed
    }

    /// Re-queue a surface onto the undo stack after it was popped by `undoClose()`.
    /// Used when an undo attempt targets the wrong pane and the surface must remain restorable.
    /// Re-queued entries are inserted at the oldest position so they don't immediately
    /// re-poison the next undo pop with the same mismatch.
    func requeueUndo(_ surfaceId: UUID) {
        guard
            var managed = activeSurfaces.removeValue(forKey: surfaceId) ?? hiddenSurfaces.removeValue(forKey: surfaceId)
        else {
            logger.warning("Cannot requeue surface \(surfaceId) for undo — surface not found")
            return
        }

        let previousPaneAttachmentId: UUID?
        if case .active(let paneId) = managed.state {
            previousPaneAttachmentId = paneId
            setOcclusion(surfaceId, visible: false)
        } else {
            previousPaneAttachmentId = nil
        }

        let expiresAt = Date().addingTimeInterval(undoTTL)
        managed.state = .pendingUndo(expiresAt: expiresAt)

        if let existingEntryIndex = undoStack.firstIndex(where: { $0.surface.id == surfaceId }) {
            let existingEntry = undoStack.remove(at: existingEntryIndex)
            existingEntry.expirationTask?.cancel()
        }

        var entry = SurfaceUndoEntry(
            surface: managed,
            previousPaneAttachmentId: previousPaneAttachmentId,
            closedAt: Date(),
            expiresAt: expiresAt
        )
        entry.expirationTask = scheduleUndoExpiration(surfaceId, at: expiresAt)
        undoStack.insert(entry, at: 0)

        updateCounts()
        logger.info("Surface requeued for undo: \(surfaceId)")
    }

    /// Check if there are surfaces that can be restored
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    // MARK: - Surface Destruction

    /// Permanently destroy a surface
    func destroy(_ surfaceId: UUID) {
        // Remove from all collections
        if let managed = activeSurfaces.removeValue(forKey: surfaceId) {
            lifecycleDelegate?.surfaceWillDestroy(managed)
            surfaceViewToId.removeValue(forKey: ObjectIdentifier(managed.surface))
        } else if let managed = hiddenSurfaces.removeValue(forKey: surfaceId) {
            lifecycleDelegate?.surfaceWillDestroy(managed)
            surfaceViewToId.removeValue(forKey: ObjectIdentifier(managed.surface))
        }

        // Remove from undo stack
        if let idx = undoStack.firstIndex(where: { $0.surface.id == surfaceId }) {
            let entry = undoStack.remove(at: idx)
            entry.expirationTask?.cancel()
            lifecycleDelegate?.surfaceWillDestroy(entry.surface)
            surfaceViewToId.removeValue(forKey: ObjectIdentifier(entry.surface.surface))
        }

        // Remove health tracking
        surfaceHealth.removeValue(forKey: surfaceId)

        updateCounts()
        logger.info("Surface destroyed: \(surfaceId)")
        // Surface.deinit will clean up PTY when ARC releases it
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
    func workingDirectory(for id: UUID) -> URL? {
        metadata(for: id)?.workingDirectory
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

    private func subscribeToGhosttyNotifications() {
        let center = NotificationCenter.default

        // Renderer health changes
        let healthObserver = center.addObserver(
            forName: Ghostty.Notification.didUpdateRendererHealth,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
            let surfaceViewId = ObjectIdentifier(surfaceView)
            let isHealthy = notification.userInfo?["healthy"] as? Bool
            Task { @MainActor [weak self] in
                self?.onRendererHealthChanged(surfaceViewId: surfaceViewId, isHealthyOverride: isHealthy)
            }
        }
        ghosttyNotificationObservers.append(healthObserver)

        // Working directory changes (OSC 7)
        let cwdObserver = center.addObserver(
            forName: Ghostty.Notification.didUpdateWorkingDirectory,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
            let surfaceViewId = ObjectIdentifier(surfaceView)
            let rawPwd = notification.userInfo?["pwd"] as? String
            Task { @MainActor [weak self] in
                self?.onWorkingDirectoryChanged(surfaceViewId: surfaceViewId, rawPwd: rawPwd)
            }
        }
        ghosttyNotificationObservers.append(cwdObserver)
    }

    private func subscribeToSurfaceNotifications(_ surfaceView: Ghostty.SurfaceView) {
        // Surface-specific notifications are handled via the global observer
        // since we map surfaceView -> UUID via surfaceViewToId
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
        guard current.metadata.workingDirectory != url else { return }

        current.metadata.workingDirectory = url
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
        surfaceHealth[id] = health

        // Update managed surface
        if var managed = activeSurfaces[id] {
            managed.health = health
            activeSurfaces[id] = managed
        } else if var managed = hiddenSurfaces[id] {
            managed.health = health
            hiddenSurfaces[id] = managed
        }

        // Only notify on change
        if previousHealth != health {
            notifyHealthDelegates(id, healthChanged: health)
            logger.info("Surface \(id) health changed: \(String(describing: health))")

            // Handle dead surfaces
            if case .dead = health {
                handleDeadSurface(id)
            }
        }
    }

    private func handleDeadSurface(_ id: UUID) {
        logger.error("Surface died unexpectedly: \(id)")

        // Notify all delegates
        notifyHealthDelegatesError(id, error: .surfaceDied)

        // Don't remove from collections - let the UI handle it
        // The container can show error state and offer restart
    }

    // MARK: - Occlusion Control

    private func setOcclusion(_ surfaceId: UUID, visible: Bool) {
        guard let managed = activeSurfaces[surfaceId] ?? hiddenSurfaces[surfaceId],
            let surface = managed.surface.surface
        else {
            return
        }
        ghostty_surface_set_occlusion(surface, visible)
    }

    /// Set focus state for a surface
    func setFocus(_ surfaceId: UUID, focused: Bool) {
        guard let managed = activeSurfaces[surfaceId],
            let surface = managed.surface.surface
        else {
            RestoreTrace.log(
                "SurfaceManager.setFocus skipped surface=\(surfaceId) focused=\(focused) active=\(activeSurfaces[surfaceId] != nil)"
            )
            return
        }
        ghostty_surface_set_focus(surface, focused)
        RestoreTrace.log("SurfaceManager.setFocus surface=\(surfaceId) focused=\(focused)")
    }

    /// Sync all surface focus states. Only activeSurfaceId gets focus=true; all others get false.
    /// Mirrors Ghostty's BaseTerminalController.syncFocusToSurfaceTree() pattern.
    func syncFocus(activeSurfaceId: UUID?) {
        RestoreTrace.log(
            "SurfaceManager.syncFocus activeSurface=\(activeSurfaceId?.uuidString ?? "nil") activeCount=\(activeSurfaces.count)"
        )
        for (id, managed) in activeSurfaces {
            guard let surface = managed.surface.surface else { continue }
            ghostty_surface_set_focus(surface, id == activeSurfaceId)
            RestoreTrace.log("SurfaceManager.syncFocus set surface=\(id) focused=\(id == activeSurfaceId)")
        }
    }
}

// MARK: - Undo Expiration

extension SurfaceManager {

    private func scheduleUndoExpiration(_ surfaceId: UUID, at date: Date) -> Task<Void, Never> {
        Task { @MainActor in
            let delay = date.timeIntervalSinceNow
            if delay > 0 {
                try? await clock.sleep(for: .seconds(delay))
            }

            guard !Task.isCancelled else { return }
            expireUndoEntry(surfaceId)
        }
    }

    private func expireUndoEntry(_ surfaceId: UUID) {
        guard let idx = undoStack.firstIndex(where: { $0.surface.id == surfaceId }) else {
            return
        }

        let entry = undoStack.remove(at: idx)
        logger.info("Undo entry expired, destroying surface: \(surfaceId)")

        // Destroy the surface
        lifecycleDelegate?.surfaceWillDestroy(entry.surface)
        surfaceViewToId.removeValue(forKey: ObjectIdentifier(entry.surface.surface))
        surfaceHealth.removeValue(forKey: surfaceId)
        // ARC will clean up the surface
    }
}

// MARK: - Private Helpers

extension SurfaceManager {

    private func updateCounts() {
        activeSurfaceCount = activeSurfaces.count
        hiddenSurfaceCount = hiddenSurfaces.count
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
        surfaceViewToId[ObjectIdentifier(surfaceView)]
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
