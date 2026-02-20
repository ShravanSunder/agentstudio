import AppKit
import Foundation
import GhosttyKit
import os

private let logger = Logger(subsystem: "com.agentstudio", category: "SurfaceManager")

/// Manages Ghostty surface lifecycle independent of UI containers
/// Provides crash isolation, health monitoring, and undo support
@MainActor
final class SurfaceManager: ObservableObject {
    static let shared = SurfaceManager()

    // MARK: - Published State

    /// Count of active surfaces (for observation)
    @Published private(set) var activeSurfaceCount: Int = 0

    /// Count of hidden surfaces
    @Published private(set) var hiddenSurfaceCount: Int = 0

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
    var undoTTL: TimeInterval = 300

    /// Maximum retry count for surface creation
    var maxCreationRetries: Int = 2

    /// Health check interval in seconds
    var healthCheckInterval: TimeInterval = 2.0

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

    /// Health check timer
    private var healthCheckTimer: Timer?

    /// Checkpoint file URL
    private let checkpointURL: URL

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.checkpointURL = appSupport.appending(path: "surface-checkpoint.json")

        setupHealthMonitoring()
        subscribeToGhosttyNotifications()

        logger.info("SurfaceManager initialized")
    }

    deinit {
        healthCheckTimer?.invalidate()
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

            // Subscribe to this surface's notifications
            subscribeToSurfaceNotifications(surfaceView)

            // Update counts
            updateCounts()

            // Notify delegate
            lifecycleDelegate?.surfaceDidCreate(managed)

            logger.info("Surface created: \(managed.id)")
            return .success(managed)
        }

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
        // Check hidden surfaces first
        if var managed = hiddenSurfaces.removeValue(forKey: surfaceId) {
            managed.state = .active(paneId: paneId)
            managed.metadata.lastActiveAt = Date()
            activeSurfaces[surfaceId] = managed

            // Resume rendering
            setOcclusion(surfaceId, visible: true)

            updateCounts()
            logger.info("Surface attached: \(surfaceId) to pane \(paneId)")
            return managed.surface
        }

        // Check undo stack
        if let idx = undoStack.firstIndex(where: { $0.surface.id == surfaceId }) {
            var entry = undoStack.remove(at: idx)
            entry.expirationTask?.cancel()

            var managed = entry.surface
            managed.state = .active(paneId: paneId)
            managed.metadata.lastActiveAt = Date()
            activeSurfaces[surfaceId] = managed

            setOcclusion(surfaceId, visible: true)

            updateCounts()
            logger.info("Surface restored from undo: \(surfaceId)")
            return managed.surface
        }

        // Check if already active (re-attach)
        if let managed = activeSurfaces[surfaceId] {
            var updated = managed
            updated.state = .active(paneId: paneId)
            updated.metadata.lastActiveAt = Date()
            activeSurfaces[surfaceId] = updated
            return managed.surface
        }

        logger.warning("Surface not found for attach: \(surfaceId)")
        return nil
    }

    /// Detach a surface from its container
    /// - Parameters:
    ///   - surfaceId: ID of the surface to detach
    ///   - reason: Why the surface is being detached
    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        guard var managed = activeSurfaces.removeValue(forKey: surfaceId) else {
            logger.warning("Surface not found for detach: \(surfaceId)")
            return
        }

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
        guard var entry = undoStack.popLast() else {
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
        center.addObserver(
            self,
            selector: #selector(onRendererHealthChanged),
            name: Ghostty.Notification.didUpdateRendererHealth,
            object: nil
        )

        // Working directory changes (OSC 7)
        center.addObserver(
            self,
            selector: #selector(onWorkingDirectoryChanged),
            name: Ghostty.Notification.didUpdateWorkingDirectory,
            object: nil
        )
    }

    private func subscribeToSurfaceNotifications(_ surfaceView: Ghostty.SurfaceView) {
        // Surface-specific notifications are handled via the global observer
        // since we map surfaceView -> UUID via surfaceViewToId
    }

    @objc private func onRendererHealthChanged(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let surfaceId = surfaceViewToId[ObjectIdentifier(surfaceView)]
        else {
            return
        }

        // Check health from userInfo or surfaceView property
        let isHealthy = (notification.userInfo?["healthy"] as? Bool) ?? surfaceView.healthy

        if isHealthy {
            updateHealth(surfaceId, .healthy)
        } else {
            updateHealth(surfaceId, .unhealthy(reason: .rendererUnhealthy))
        }
    }

    @objc private func onWorkingDirectoryChanged(_ notification: Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
            let surfaceId = surfaceViewToId[ObjectIdentifier(surfaceView)]
        else {
            return
        }

        let rawPwd = notification.userInfo?["pwd"] as? String
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

        // Post higher-level notification for upstream consumers
        var userInfo: [String: Any] = ["surfaceId": surfaceId]
        if let url {
            userInfo["url"] = url
        }
        NotificationCenter.default.post(
            name: Ghostty.Notification.surfaceCWDChanged,
            object: self,
            userInfo: userInfo
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
            return
        }
        ghostty_surface_set_focus(surface, focused)
    }

    /// Sync all surface focus states. Only activeSurfaceId gets focus=true; all others get false.
    /// Mirrors Ghostty's BaseTerminalController.syncFocusToSurfaceTree() pattern.
    func syncFocus(activeSurfaceId: UUID?) {
        for (id, managed) in activeSurfaces {
            guard let surface = managed.surface.surface else { continue }
            ghostty_surface_set_focus(surface, id == activeSurfaceId)
        }
    }
}

// MARK: - Undo Expiration

extension SurfaceManager {

    private func scheduleUndoExpiration(_ surfaceId: UUID, at date: Date) -> Task<Void, Never> {
        Task { @MainActor in
            let delay = date.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
