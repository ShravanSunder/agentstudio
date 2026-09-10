import CoreServices
import Foundation

package enum DarwinSharedExactItemNativeStream {
    private final class CallbackContext {
        let eventHandler: @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
        init(eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void) {
            self.eventHandler = eventHandler
        }
    }

    private final class StreamLifetime: DarwinSharedExactItemStreamLifetime, @unchecked Sendable {
        private let nativeLifetime: DarwinFSEventNativeStreamLifetime
        init(stream: FSEventStreamRef, queue: DispatchQueue) {
            nativeLifetime = DarwinFSEventNativeStreamLifetime(
                stream: stream,
                queue: queue
            )
        }
        func retire() { nativeLifetime.scheduleRetirement() }
        func flush() -> Bool { nativeLifetime.flush() }
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
                    path: unsafeBitCast(value, to: CFString.self) as String, eventId: ids[index], flags: flags[index]))
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
        parentKey: DarwinSharedExactItemParentKey, streamGeneration: UInt64,
        eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        let callbackContext = CallbackContext(eventHandler: eventHandler)
        let callbackContextPointer = Unmanaged.passUnretained(callbackContext).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: callbackContextPointer,
            retain: retainCallback,
            release: releaseCallback,
            copyDescription: nil
        )
        let watchedPaths = [parentKey.parentPath as NSString] as CFArray
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &streamContext, watchedPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1,
                DarwinFSEventStreamConfiguration.continuityFlags)
        else {
            return nil
        }
        guard
            DarwinFSEventStreamConfiguration.installPrivateStagingExclusions(
                DarwinFSEventStreamConfiguration.privateStagingExclusionPaths(sharedParentPath: parentKey.parentPath),
                on: stream)
        else {
            FSEventStreamRelease(stream)
            return nil
        }
        let queue = DispatchQueue(
            label: "com.agentstudio.fsevents.shared.\(parentKey.volumeSystemNumber).\(streamGeneration)", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        return StreamLifetime(stream: stream, queue: queue)
    }
}
