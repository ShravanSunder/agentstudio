import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public struct UnixSocketEndpoint: Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct UnixSocketTransportError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case unsupportedPlatform
        case pathTooLong
        case socketCreationFailed
        case bindFailed
        case listenFailed
        case acceptFailed
        case connectFailed
        case readFailed
        case writeFailed
        case receiveLimitExceeded
        case closeFailed
        case peerCredentialsUnavailable
    }

    public let reason: Reason
    public let errnoCode: Int32

    public init(reason: Reason, errnoCode: Int32 = 0) {
        self.reason = reason
        self.errnoCode = errnoCode
    }
}

public struct PeerCredentials: Equatable, Sendable {
    public let userIdentifier: uid_t
    public let groupIdentifier: gid_t

    public init(userIdentifier: uid_t, groupIdentifier: gid_t) {
        self.userIdentifier = userIdentifier
        self.groupIdentifier = groupIdentifier
    }
}

public protocol PeerCredentialProviding: Sendable {
    func credentials(forAcceptedSocket fileDescriptor: Int32) throws -> PeerCredentials
}

public struct DarwinPeerCredentialProvider: PeerCredentialProviding {
    public init() {}

    public func credentials(forAcceptedSocket fileDescriptor: Int32) throws -> PeerCredentials {
        #if canImport(Darwin)
            var userIdentifier: uid_t = 0
            var groupIdentifier: gid_t = 0
            guard getpeereid(fileDescriptor, &userIdentifier, &groupIdentifier) == 0 else {
                throw UnixSocketTransportError(reason: .peerCredentialsUnavailable, errnoCode: errno)
            }

            return PeerCredentials(userIdentifier: userIdentifier, groupIdentifier: groupIdentifier)
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }
}

public final class UnixSocketConnection: @unchecked Sendable {
    public let fileDescriptor: Int32

    private let closeLock = NSLock()
    private var isClosed = false

    public init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        close()
    }

    public func send(_ data: Data) throws {
        #if canImport(Darwin)
            try data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }

                var writtenByteCount = 0
                while writtenByteCount < rawBuffer.count {
                    let result = Darwin.write(
                        fileDescriptor,
                        baseAddress.advanced(by: writtenByteCount),
                        rawBuffer.count - writtenByteCount
                    )

                    if result < 0 {
                        if errno == EINTR {
                            continue
                        }
                        throw UnixSocketTransportError(reason: .writeFailed, errnoCode: errno)
                    }

                    writtenByteCount += result
                }
            }
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }

    public func receive(maxBytes: Int) throws -> Data {
        #if canImport(Darwin)
            precondition(maxBytes > 0, "maxBytes must be positive")

            var buffer = [UInt8](repeating: 0, count: maxBytes)
            let readByteCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
            }

            if readByteCount < 0 {
                if errno == EINTR {
                    return try receive(maxBytes: maxBytes)
                }
                throw UnixSocketTransportError(reason: .readFailed, errnoCode: errno)
            }

            if readByteCount > maxBytes {
                throw UnixSocketTransportError(reason: .receiveLimitExceeded)
            }

            return Data(buffer.prefix(readByteCount))
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }

    public func close() {
        #if canImport(Darwin)
            closeLock.withLock {
                guard !isClosed else {
                    return
                }

                _ = Darwin.shutdown(fileDescriptor, SHUT_RDWR)
                _ = Darwin.close(fileDescriptor)
                isClosed = true
            }
        #endif
    }
}

public enum UnixSocketClient {
    public static func connect(endpoint: UnixSocketEndpoint) throws -> UnixSocketConnection {
        #if canImport(Darwin)
            let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fileDescriptor >= 0 else {
                throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
            }

            do {
                try UnixSocketOptions.disableSigPipe(fileDescriptor: fileDescriptor)
                try SocketAddress.withUnixAddress(path: endpoint.path) { address, length in
                    guard Darwin.connect(fileDescriptor, address, length) == 0 else {
                        throw UnixSocketTransportError(reason: .connectFailed, errnoCode: errno)
                    }
                }
                return UnixSocketConnection(fileDescriptor: fileDescriptor)
            } catch {
                _ = Darwin.close(fileDescriptor)
                throw error
            }
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }
}

public final class UnixSocketListener: @unchecked Sendable {
    public let endpoint: UnixSocketEndpoint

    private let stateLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "com.agentstudio.ipc.unix-socket-listener")
    private let acceptQueueSpecificKey = DispatchSpecificKey<Bool>()
    private var fileDescriptor: Int32?
    private var isStopping = false

    public init(endpoint: UnixSocketEndpoint) {
        self.endpoint = endpoint
        acceptQueue.setSpecific(key: acceptQueueSpecificKey, value: true)
    }

    deinit {
        stop()
    }

    public func start(onConnection: @escaping @Sendable (UnixSocketConnection) throws -> Void) throws {
        #if canImport(Darwin)
            let listenerDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard listenerDescriptor >= 0 else {
                throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
            }

            do {
                try SocketAddress.withUnixAddress(path: endpoint.path) { address, length in
                    guard Darwin.bind(listenerDescriptor, address, length) == 0 else {
                        throw UnixSocketTransportError(reason: .bindFailed, errnoCode: errno)
                    }
                }

                guard Darwin.listen(listenerDescriptor, SOMAXCONN) == 0 else {
                    throw UnixSocketTransportError(reason: .listenFailed, errnoCode: errno)
                }

                stateLock.withLock {
                    fileDescriptor = listenerDescriptor
                    isStopping = false
                }

                acceptQueue.async { [self] in
                    acceptLoop(onConnection: onConnection)
                }
            } catch {
                _ = Darwin.close(listenerDescriptor)
                throw error
            }
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }

    public func stop() {
        #if canImport(Darwin)
            let descriptor = stateLock.withLock {
                isStopping = true
                let descriptor = fileDescriptor
                fileDescriptor = nil
                return descriptor
            }

            if let descriptor {
                _ = Darwin.shutdown(descriptor, SHUT_RDWR)
                _ = Darwin.close(descriptor)
            }

            if descriptor != nil && DispatchQueue.getSpecific(key: acceptQueueSpecificKey) != true {
                wakeAcceptLoop()
            }

            _ = endpoint.path.withCString { Darwin.unlink($0) }

            if DispatchQueue.getSpecific(key: acceptQueueSpecificKey) != true {
                acceptQueue.sync {}
            }
        #endif
    }

    private func wakeAcceptLoop() {
        #if canImport(Darwin)
            guard let connection = try? UnixSocketClient.connect(endpoint: endpoint) else {
                return
            }
            connection.close()
        #endif
    }

    private func acceptLoop(onConnection: @escaping @Sendable (UnixSocketConnection) throws -> Void) {
        #if canImport(Darwin)
            while true {
                let descriptor = stateLock.withLock {
                    fileDescriptor
                }
                guard let descriptor else {
                    return
                }

                let acceptedDescriptor = Darwin.accept(descriptor, nil, nil)
                if acceptedDescriptor < 0 {
                    let shouldStop = stateLock.withLock {
                        isStopping
                    }
                    if shouldStop || errno == EBADF || errno == EINVAL {
                        return
                    }
                    continue
                }

                let shouldStopAfterAccept = stateLock.withLock {
                    isStopping || fileDescriptor == nil
                }
                if shouldStopAfterAccept {
                    _ = Darwin.close(acceptedDescriptor)
                    return
                }

                do {
                    try UnixSocketOptions.disableSigPipe(fileDescriptor: acceptedDescriptor)
                } catch {
                    _ = Darwin.close(acceptedDescriptor)
                    continue
                }

                let connection = UnixSocketConnection(fileDescriptor: acceptedDescriptor)
                do {
                    try onConnection(connection)
                } catch {
                    connection.close()
                }
            }
        #endif
    }
}

public enum UnixSocketOptions {
    public static func disableSigPipe(fileDescriptor: Int32) throws {
        #if canImport(Darwin)
            var value: Int32 = 1
            guard
                Darwin.setsockopt(
                    fileDescriptor,
                    SOL_SOCKET,
                    SO_NOSIGPIPE,
                    &value,
                    socklen_t(MemoryLayout.size(ofValue: value))
                ) == 0
            else {
                throw UnixSocketTransportError(reason: .socketCreationFailed, errnoCode: errno)
            }
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }
}

private enum SocketAddress {
    static func withUnixAddress<Result>(
        path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) throws -> Result {
        #if canImport(Darwin)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)

            let pathBytes = path.utf8CString.map { UInt8(bitPattern: $0) }
            let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= pathCapacity else {
                throw UnixSocketTransportError(reason: .pathTooLong)
            }

            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.copyBytes(from: pathBytes)
            }

            let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
            return try withUnsafePointer(to: &address) { addressPointer in
                try addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    try body(socketAddress, length)
                }
            }
        #else
            throw UnixSocketTransportError(reason: .unsupportedPlatform)
        #endif
    }
}
