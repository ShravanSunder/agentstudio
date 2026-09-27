import Darwin
import Foundation
import NIOCore

/// The one stdout line the development server prints once its listener is bound, so an
/// owning harness waits on this event instead of polling the health route.
enum BridgeDevelopmentServerReadinessAnnouncement {
    static func line(boundTo channel: any Channel, processIdentifier: Int32) -> String? {
        guard let port = channel.localAddress?.port else { return nil }
        return "bridge-development-server ready port=\(port) pid=\(processIdentifier)\n"
    }

    /// `FileHandle.write` is an unbuffered write(2), so the line reaches the pipe immediately.
    static func announce(boundTo channel: any Channel) {
        guard let line = line(boundTo: channel, processIdentifier: getpid()) else { return }
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}
