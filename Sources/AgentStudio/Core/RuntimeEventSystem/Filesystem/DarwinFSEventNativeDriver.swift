import CoreServices
import Dispatch
import Foundation

enum DarwinFSEventNativeStreamCreationFailure: Error, Equatable, Sendable {
    case nativeCreateRejected
}

final class DarwinFSEventNativeStreamHandle: @unchecked Sendable {
    fileprivate enum Storage {
        case native(FSEventStreamRef)
        case test(UUID)
    }

    fileprivate let storage: Storage

    fileprivate init(storage: Storage) {
        self.storage = storage
    }

    static func testHandle(identity: UUID = UUID()) -> DarwinFSEventNativeStreamHandle {
        DarwinFSEventNativeStreamHandle(storage: .test(identity))
    }
}

struct DarwinFSEventNativeStreamCreationRequest: @unchecked Sendable {
    let resolvedRootPath: String
    let callbackQueue: DispatchQueue
    let callback: FSEventStreamCallback
    let callbackContextPointer: UnsafeMutableRawPointer
}

protocol DarwinFSEventNativeDriver: Sendable {
    func createStream(
        request: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure>
    func startStream(_ stream: DarwinFSEventNativeStreamHandle) -> Bool
    func stopStream(_ stream: DarwinFSEventNativeStreamHandle)
    func invalidateStream(_ stream: DarwinFSEventNativeStreamHandle)
    func releaseStream(_ stream: DarwinFSEventNativeStreamHandle)
}

protocol DarwinFSEventCallbackQueueBarrier: Sendable {
    func waitForBarrier(on callbackQueue: DispatchQueue) async
}

struct DarwinFSEventAsyncCallbackQueueBarrier: DarwinFSEventCallbackQueueBarrier {
    func waitForBarrier(on callbackQueue: DispatchQueue) async {
        await withCheckedContinuation { continuation in
            callbackQueue.async {
                continuation.resume()
            }
        }
    }
}

struct DarwinFSEventSystemNativeDriver: DarwinFSEventNativeDriver {
    private static let latency: CFTimeInterval = 0.1

    func createStream(
        request: DarwinFSEventNativeStreamCreationRequest
    ) -> Result<DarwinFSEventNativeStreamHandle, DarwinFSEventNativeStreamCreationFailure> {
        var streamContext = FSEventStreamContext(
            version: 0,
            info: request.callbackContextPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let watchPaths = [request.resolvedRootPath as NSString] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                request.callback,
                &streamContext,
                watchPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                Self.latency,
                flags
            )
        else {
            return .failure(.nativeCreateRejected)
        }
        FSEventStreamSetDispatchQueue(stream, request.callbackQueue)
        return .success(DarwinFSEventNativeStreamHandle(storage: .native(stream)))
    }

    func startStream(_ stream: DarwinFSEventNativeStreamHandle) -> Bool {
        FSEventStreamStart(nativeStream(from: stream))
    }

    func stopStream(_ stream: DarwinFSEventNativeStreamHandle) {
        FSEventStreamStop(nativeStream(from: stream))
    }

    func invalidateStream(_ stream: DarwinFSEventNativeStreamHandle) {
        FSEventStreamInvalidate(nativeStream(from: stream))
    }

    func releaseStream(_ stream: DarwinFSEventNativeStreamHandle) {
        FSEventStreamRelease(nativeStream(from: stream))
    }

    private func nativeStream(from stream: DarwinFSEventNativeStreamHandle) -> FSEventStreamRef {
        switch stream.storage {
        case .native(let nativeStream):
            nativeStream
        case .test:
            preconditionFailure("system native driver cannot operate on a test stream handle")
        }
    }
}
