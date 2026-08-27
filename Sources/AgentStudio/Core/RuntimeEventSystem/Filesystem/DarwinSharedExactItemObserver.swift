import CoreServices
import Foundation

package enum DarwinFSEventStreamConfiguration {
    package static let continuityFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagWatchRoot
    )
}

package struct DarwinSharedExactItemRawEvent: Sendable {
    package let path: String
    package let eventId: FSEventStreamEventId
    package let flags: FSEventStreamEventFlags
}

package protocol DarwinSharedExactItemStreamLifetime: AnyObject, Sendable {
    func retire()
}

package typealias DarwinSharedExactItemStreamFactory =
    @Sendable (
        DarwinSharedExactItemParentKey,
        UInt64,
        @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)?

package struct DarwinSharedExactItemObservationSnapshot: Sendable {
    package let observerCount: Int
    package let bindingCount: Int
    package let generationByParent: [DarwinSharedExactItemParentKey: UInt64]
    package let referenceCountByParent: [DarwinSharedExactItemParentKey: Int]
}

package final class DarwinSharedExactItemObserverRegistry: @unchecked Sendable {
    private struct BindingValidation: Sendable {
        let generation: UInt64
        let isCurrent: @Sendable () -> Bool
    }

    private struct ObserverState {
        let generation: UInt64
        let streamLifetime: any DarwinSharedExactItemStreamLifetime
        var exactPathsByWorktreeId: [UUID: Set<String>]
        var worktreeIdsByExactPath: [String: Set<UUID>]
        var latestEventId: FSEventStreamEventId?
    }

    private struct StartedObserver {
        let generation: UInt64
        let streamLifetime: any DarwinSharedExactItemStreamLifetime
    }

    private static let uncertaintyFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount
    )

    private let lifecycleCondition = NSCondition()
    private let streamFactory: DarwinSharedExactItemStreamFactory
    private let recordRawEvents: @Sendable (UUID, [DarwinFSEventClassifiedRawEvent]) -> Void
    private let markUncertain: @Sendable (UUID) -> Void
    private let yieldFullGitRefresh: @Sendable (UUID) -> Void
    private var nextStreamGeneration: UInt64 = 0
    private var observerByParent: [DarwinSharedExactItemParentKey: ObserverState] = [:]
    private var exactItemsByParentByWorktreeId: [UUID: [DarwinSharedExactItemParentKey: Set<String>]] = [:]
    private var bindingValidationByWorktreeId: [UUID: BindingValidation] = [:]
    private var sharedDependentWorktreeIds: Set<UUID> = []
    private var startingParentKeys: Set<DarwinSharedExactItemParentKey> = []
    private var hasShutdown = false

    package init(
        streamFactory: @escaping DarwinSharedExactItemStreamFactory,
        recordRawEvents:
            @escaping @Sendable (
                UUID,
                [DarwinFSEventClassifiedRawEvent]
            ) -> Void,
        markUncertain: @escaping @Sendable (UUID) -> Void,
        yieldFullGitRefresh: @escaping @Sendable (UUID) -> Void
    ) {
        self.streamFactory = streamFactory
        self.recordRawEvents = recordRawEvents
        self.markUncertain = markUncertain
        self.yieldFullGitRefresh = yieldFullGitRefresh
    }

    package func bind(
        worktreeId: UUID,
        bindingGeneration: UInt64,
        exactItemsByParent: [DarwinSharedExactItemParentKey: Set<String>],
        bindingIsCurrent: @escaping @Sendable () -> Bool
    ) -> Bool {
        guard bindingIsCurrent() else { return false }
        let desiredExactItemsByParent = exactItemsByParent.filter { !$0.value.isEmpty }
        var startedObservers: [DarwinSharedExactItemParentKey: StartedObserver] = [:]

        while true {
            lifecycleCondition.lock()
            guard !hasShutdown else {
                lifecycleCondition.unlock()
                retire(startedObservers.values.map(\.streamLifetime))
                return false
            }

            let desiredParentKeys = Set(desiredExactItemsByParent.keys)
            if !desiredParentKeys.isDisjoint(with: startingParentKeys) {
                lifecycleCondition.wait()
                lifecycleCondition.unlock()
                continue
            }

            let missingParentKeys = desiredParentKeys.filter {
                observerByParent[$0] == nil
            }
            if missingParentKeys.isEmpty {
                guard bindingIsCurrent() else {
                    lifecycleCondition.unlock()
                    retire(startedObservers.values.map(\.streamLifetime))
                    return false
                }
                let retiredStreamLifetimes = replaceBindingLocked(
                    worktreeId: worktreeId,
                    bindingGeneration: bindingGeneration,
                    bindingIsCurrent: bindingIsCurrent,
                    desiredExactItemsByParent: desiredExactItemsByParent
                )
                lifecycleCondition.unlock()
                retire(retiredStreamLifetimes)
                return true
            }

            let generationByMissingParent = Dictionary(
                uniqueKeysWithValues: missingParentKeys.map { parentKey in
                    nextStreamGeneration &+= 1
                    return (parentKey, nextStreamGeneration)
                }
            )
            startingParentKeys.formUnion(missingParentKeys)
            lifecycleCondition.unlock()

            for (parentKey, streamGeneration) in generationByMissingParent {
                guard
                    let streamLifetime = streamFactory(
                        parentKey,
                        streamGeneration,
                        { [weak self] rawEvents in
                            self?.receive(
                                parentKey: parentKey,
                                streamGeneration: streamGeneration,
                                rawEvents: rawEvents
                            )
                        }
                    )
                else {
                    continue
                }
                startedObservers[parentKey] = StartedObserver(
                    generation: streamGeneration,
                    streamLifetime: streamLifetime
                )
            }

            lifecycleCondition.lock()
            startingParentKeys.subtract(missingParentKeys)
            let everyStreamStarted = Set(startedObservers.keys).isSuperset(of: missingParentKeys)
            guard !hasShutdown, everyStreamStarted, bindingIsCurrent() else {
                lifecycleCondition.broadcast()
                lifecycleCondition.unlock()
                retire(startedObservers.values.map(\.streamLifetime))
                return false
            }

            var redundantStreamLifetimes: [any DarwinSharedExactItemStreamLifetime] = []
            for (parentKey, startedObserver) in startedObservers {
                if observerByParent[parentKey] == nil {
                    observerByParent[parentKey] = ObserverState(
                        generation: startedObserver.generation,
                        streamLifetime: startedObserver.streamLifetime,
                        exactPathsByWorktreeId: [:],
                        worktreeIdsByExactPath: [:],
                        latestEventId: nil
                    )
                } else {
                    redundantStreamLifetimes.append(startedObserver.streamLifetime)
                }
            }
            let retiredStreamLifetimes = replaceBindingLocked(
                worktreeId: worktreeId,
                bindingGeneration: bindingGeneration,
                bindingIsCurrent: bindingIsCurrent,
                desiredExactItemsByParent: desiredExactItemsByParent
            )
            lifecycleCondition.broadcast()
            lifecycleCondition.unlock()
            retire(redundantStreamLifetimes + retiredStreamLifetimes)
            return true
        }
    }

    package func unbind(worktreeId: UUID, bindingGeneration: UInt64? = nil) {
        lifecycleCondition.lock()
        if let bindingGeneration,
            bindingValidationByWorktreeId[worktreeId]?.generation != bindingGeneration
        {
            lifecycleCondition.unlock()
            return
        }
        let retiredStreamLifetimes = replaceBindingLocked(
            worktreeId: worktreeId,
            bindingGeneration: nil,
            bindingIsCurrent: nil,
            desiredExactItemsByParent: [:]
        )
        lifecycleCondition.unlock()
        retire(retiredStreamLifetimes)
    }

    package func hasBinding(worktreeId: UUID) -> Bool {
        lifecycleCondition.withLock {
            sharedDependentWorktreeIds.contains(worktreeId)
                && bindingValidationByWorktreeId[worktreeId]?.isCurrent() == true
        }
    }

    package func snapshot() -> DarwinSharedExactItemObservationSnapshot {
        lifecycleCondition.withLock {
            DarwinSharedExactItemObservationSnapshot(
                observerCount: observerByParent.count,
                bindingCount: sharedDependentWorktreeIds.count,
                generationByParent: observerByParent.mapValues(\.generation),
                referenceCountByParent: observerByParent.mapValues {
                    $0.exactPathsByWorktreeId.count
                }
            )
        }
    }

    package func receive(
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64,
        rawEvents: [DarwinSharedExactItemRawEvent]
    ) {
        guard !rawEvents.isEmpty else { return }

        lifecycleCondition.lock()
        guard !hasShutdown,
            var observer = observerByParent[parentKey],
            observer.generation == streamGeneration
        else {
            lifecycleCondition.unlock()
            return
        }

        var mutationEventsByWorktreeId: [UUID: [DarwinFSEventClassifiedRawEvent]] = [:]
        var uncertainWorktreeIds: Set<UUID> = []
        var fullGitRefreshWorktreeIds: Set<UUID> = []
        var shouldRetireObserver = false
        let dependentWorktreeIds = Set(
            observer.exactPathsByWorktreeId.keys.filter {
                bindingValidationByWorktreeId[$0]?.isCurrent() == true
            })

        for rawEvent in rawEvents {
            let normalizedPath = DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath(
                rawEvent.path
            )
            let cursorRegressed = observer.latestEventId.map { rawEvent.eventId < $0 } ?? false
            observer.latestEventId = rawEvent.eventId
            let exactSubscribers = (observer.worktreeIdsByExactPath[normalizedPath] ?? []).filter {
                bindingValidationByWorktreeId[$0]?.isCurrent() == true
            }
            for worktreeId in exactSubscribers {
                mutationEventsByWorktreeId[worktreeId, default: []].append(
                    DarwinFSEventClassifiedRawEvent(
                        eventId: rawEvent.eventId,
                        flags: rawEvent.flags,
                        hasRelevantMutation: true
                    )
                )
            }
            fullGitRefreshWorktreeIds.formUnion(exactSubscribers)

            let hasUncertainFlags = rawEvent.flags & Self.uncertaintyFlags != 0
            let hasAmbiguousAncestorCoverage = observer.worktreeIdsByExactPath.keys.contains { exactPath in
                exactPath.hasPrefix(normalizedPath + "/")
            }
            if hasUncertainFlags || cursorRegressed || hasAmbiguousAncestorCoverage {
                uncertainWorktreeIds.formUnion(dependentWorktreeIds)
                fullGitRefreshWorktreeIds.formUnion(dependentWorktreeIds)
            }
            if rawEvent.flags
                & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
            {
                shouldRetireObserver = true
            }
        }

        var retiredStreamLifetime: (any DarwinSharedExactItemStreamLifetime)?
        if shouldRetireObserver {
            retiredStreamLifetime = retireObserverLocked(parentKey: parentKey)
        } else {
            observerByParent[parentKey] = observer
        }
        lifecycleCondition.unlock()

        for worktreeId in mutationEventsByWorktreeId.keys.sorted(by: Self.sortWorktreeIds) {
            guard let events = mutationEventsByWorktreeId[worktreeId] else { continue }
            recordRawEvents(worktreeId, events)
        }
        for worktreeId in uncertainWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            markUncertain(worktreeId)
        }
        for worktreeId in fullGitRefreshWorktreeIds.sorted(by: Self.sortWorktreeIds) {
            yieldFullGitRefresh(worktreeId)
        }
        if let retiredStreamLifetime {
            retiredStreamLifetime.retire()
        }
    }

    package func shutdown() {
        lifecycleCondition.lock()
        guard !hasShutdown else {
            lifecycleCondition.unlock()
            return
        }
        hasShutdown = true
        let streamLifetimes = observerByParent.values.map(\.streamLifetime)
        observerByParent.removeAll(keepingCapacity: false)
        exactItemsByParentByWorktreeId.removeAll(keepingCapacity: false)
        bindingValidationByWorktreeId.removeAll(keepingCapacity: false)
        sharedDependentWorktreeIds.removeAll(keepingCapacity: false)
        lifecycleCondition.broadcast()
        lifecycleCondition.unlock()
        retire(streamLifetimes)
    }

    private func replaceBindingLocked(
        worktreeId: UUID,
        bindingGeneration: UInt64?,
        bindingIsCurrent: (@Sendable () -> Bool)?,
        desiredExactItemsByParent: [DarwinSharedExactItemParentKey: Set<String>]
    ) -> [any DarwinSharedExactItemStreamLifetime] {
        let previousExactItemsByParent = exactItemsByParentByWorktreeId[worktreeId] ?? [:]
        let allParentKeys = Set(previousExactItemsByParent.keys)
            .union(desiredExactItemsByParent.keys)
        var retiredStreamLifetimes: [any DarwinSharedExactItemStreamLifetime] = []

        for parentKey in allParentKeys {
            guard var observer = observerByParent[parentKey] else { continue }
            let previousExactPaths = previousExactItemsByParent[parentKey] ?? []
            let desiredExactPaths = desiredExactItemsByParent[parentKey] ?? []

            for exactPath in previousExactPaths.subtracting(desiredExactPaths) {
                observer.worktreeIdsByExactPath[exactPath]?.remove(worktreeId)
                if observer.worktreeIdsByExactPath[exactPath]?.isEmpty == true {
                    observer.worktreeIdsByExactPath.removeValue(forKey: exactPath)
                }
            }
            for exactPath in desiredExactPaths {
                observer.worktreeIdsByExactPath[exactPath, default: []].insert(worktreeId)
            }
            if desiredExactPaths.isEmpty {
                observer.exactPathsByWorktreeId.removeValue(forKey: worktreeId)
            } else {
                observer.exactPathsByWorktreeId[worktreeId] = desiredExactPaths
            }

            if observer.exactPathsByWorktreeId.isEmpty {
                observerByParent.removeValue(forKey: parentKey)
                retiredStreamLifetimes.append(observer.streamLifetime)
            } else {
                observerByParent[parentKey] = observer
            }
        }

        if desiredExactItemsByParent.isEmpty {
            exactItemsByParentByWorktreeId.removeValue(forKey: worktreeId)
            bindingValidationByWorktreeId.removeValue(forKey: worktreeId)
            sharedDependentWorktreeIds.remove(worktreeId)
        } else {
            guard let bindingGeneration, let bindingIsCurrent else {
                return retiredStreamLifetimes
            }
            exactItemsByParentByWorktreeId[worktreeId] = desiredExactItemsByParent
            bindingValidationByWorktreeId[worktreeId] = BindingValidation(
                generation: bindingGeneration,
                isCurrent: bindingIsCurrent
            )
            sharedDependentWorktreeIds.insert(worktreeId)
        }
        return retiredStreamLifetimes
    }

    private func retireObserverLocked(
        parentKey: DarwinSharedExactItemParentKey
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        guard let observer = observerByParent.removeValue(forKey: parentKey) else { return nil }
        for worktreeId in observer.exactPathsByWorktreeId.keys {
            exactItemsByParentByWorktreeId[worktreeId]?.removeValue(forKey: parentKey)
            if exactItemsByParentByWorktreeId[worktreeId]?.isEmpty == true {
                exactItemsByParentByWorktreeId.removeValue(forKey: worktreeId)
            }
        }
        return observer.streamLifetime
    }

    private func retire(_ streamLifetimes: [any DarwinSharedExactItemStreamLifetime]) {
        for streamLifetime in streamLifetimes {
            streamLifetime.retire()
        }
    }

    private static func sortWorktreeIds(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

package enum DarwinFSEventPathNormalizer {
    package static func lexicallyNormalizedAbsolutePath(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        guard containsNonCanonicalPathComponent(path) else { return path }

        var normalizedComponents: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !normalizedComponents.isEmpty {
                    normalizedComponents.removeLast()
                }
            default:
                normalizedComponents.append(component)
            }
        }
        guard !normalizedComponents.isEmpty else { return "/" }
        return "/" + normalizedComponents.joined(separator: "/")
    }

    private static func containsNonCanonicalPathComponent(_ path: String) -> Bool {
        if let result = path.utf8.withContiguousStorageIfAvailable(scanNonCanonicalPathComponents) {
            return result
        }
        return Array(path.utf8).withUnsafeBufferPointer(scanNonCanonicalPathComponents)
    }

    private static func scanNonCanonicalPathComponents(
        _ bytes: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        let separator = UInt8(ascii: "/")
        let dot = UInt8(ascii: ".")
        var hasConsumedLeadingSeparator = false
        var componentLength = 0
        var componentContainsOnlyDots = true
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == separator {
                if !hasConsumedLeadingSeparator {
                    hasConsumedLeadingSeparator = true
                    continue
                }
                if componentLength == 0
                    || componentContainsOnlyDots && componentLength <= 2
                {
                    return true
                }
                componentLength = 0
                componentContainsOnlyDots = true
                continue
            }

            componentLength += 1
            if byte != dot {
                componentContainsOnlyDots = false
            }
        }

        return componentContainsOnlyDots && (componentLength == 1 || componentLength == 2)
    }
}

package enum DarwinSharedExactItemNativeStream {
    private final class CallbackContext {
        let eventHandler: @Sendable ([DarwinSharedExactItemRawEvent]) -> Void

        init(eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void) {
            self.eventHandler = eventHandler
        }
    }

    private final class StreamLifetime: DarwinSharedExactItemStreamLifetime, @unchecked Sendable {
        private let lock = NSLock()
        private let stream: FSEventStreamRef
        private let queue: DispatchQueue
        private let callbackContextPointer: UnsafeMutableRawPointer
        private var hasScheduledRetirement = false

        init(
            stream: FSEventStreamRef,
            queue: DispatchQueue,
            callbackContextPointer: UnsafeMutableRawPointer
        ) {
            self.stream = stream
            self.queue = queue
            self.callbackContextPointer = callbackContextPointer
        }

        func retire() {
            let shouldScheduleRetirement = lock.withLock { () -> Bool in
                guard !hasScheduledRetirement else { return false }
                hasScheduledRetirement = true
                return true
            }
            guard shouldScheduleRetirement else { return }
            queue.async { [self] in
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                Unmanaged<CallbackContext>.fromOpaque(callbackContextPointer).release()
                _ = queue
            }
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        guard let info else { return }
        let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
        let pathArray = unsafeBitCast(paths, to: CFArray.self)
        let boundedCount = min(Int(count), CFArrayGetCount(pathArray))
        var rawEvents: [DarwinSharedExactItemRawEvent] = []
        rawEvents.reserveCapacity(boundedCount)
        for index in 0..<boundedCount {
            guard let value = CFArrayGetValueAtIndex(pathArray, index) else { continue }
            rawEvents.append(
                DarwinSharedExactItemRawEvent(
                    path: unsafeBitCast(value, to: CFString.self) as String,
                    eventId: ids[index],
                    flags: flags[index]
                )
            )
        }
        context.eventHandler(rawEvents)
    }

    package static func start(
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64,
        eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        let callbackContext = CallbackContext(eventHandler: eventHandler)
        let callbackContextPointer = Unmanaged.passRetained(callbackContext).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: callbackContextPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchedPaths = [parentKey.parentPath as NSString] as CFArray
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &streamContext,
                watchedPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.1,
                DarwinFSEventStreamConfiguration.continuityFlags
            )
        else {
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPointer).release()
            return nil
        }
        let queue = DispatchQueue(
            label: "com.agentstudio.fsevents.shared.\(parentKey.volumeSystemNumber).\(streamGeneration)",
            qos: .utility
        )
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPointer).release()
            return nil
        }
        return StreamLifetime(
            stream: stream,
            queue: queue,
            callbackContextPointer: callbackContextPointer
        )
    }
}
