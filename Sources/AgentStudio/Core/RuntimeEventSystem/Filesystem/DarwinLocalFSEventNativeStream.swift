import CoreServices
import Foundation

package enum DarwinLocalFSEventNativeStream {
    private final class CallbackContext {
        let eventHandler: @Sendable ([DarwinLocalFSEventRawEvent]) -> Void

        init(eventHandler: @escaping @Sendable ([DarwinLocalFSEventRawEvent]) -> Void) {
            self.eventHandler = eventHandler
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        guard let info else { return }

        let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
        let pathArray = unsafeBitCast(paths, to: CFArray.self)
        let boundedCount = min(Int(count), CFArrayGetCount(pathArray))
        var rawEvents: [DarwinLocalFSEventRawEvent] = []
        rawEvents.reserveCapacity(boundedCount)
        for index in 0..<boundedCount {
            guard let value = CFArrayGetValueAtIndex(pathArray, index) else { continue }
            rawEvents.append(
                DarwinLocalFSEventRawEvent(
                    path: unsafeBitCast(value, to: CFString.self) as String,
                    eventId: ids[index],
                    flags: flags[index]
                )
            )
        }
        context.eventHandler(rawEvents)
    }

    private static let retainCallback: CFAllocatorRetainCallBack = { info in
        guard let info else { return nil }
        return UnsafeRawPointer(
            Unmanaged<CallbackContext>.fromOpaque(info).retain().toOpaque()
        )
    }

    private static let releaseCallback: CFAllocatorReleaseCallBack = { info in
        guard let info else { return }
        Unmanaged<CallbackContext>.fromOpaque(info).release()
    }

    package static func start(
        request: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        let callbackContext = CallbackContext(eventHandler: request.eventHandler)
        let callbackContextPointer = Unmanaged.passUnretained(callbackContext).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: callbackContextPointer,
            retain: retainCallback,
            release: releaseCallback,
            copyDescription: nil
        )
        let watchedPaths = request.watchedPaths.map { $0 as NSString } as CFArray
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
            return nil
        }

        guard
            DarwinFSEventStreamConfiguration.installPrivateStagingExclusions(
                request.privateStagingExclusionPaths,
                on: stream
            )
        else {
            FSEventStreamRelease(stream)
            return nil
        }

        let queue = DispatchQueue(
            label: "com.agentstudio.fsevents.\(request.worktreeId.uuidString).\(request.lifecycleGeneration)",
            qos: .utility
        )
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        return DarwinFSEventNativeStreamLifetime(
            stream: stream,
            queue: queue
        )
    }
}
