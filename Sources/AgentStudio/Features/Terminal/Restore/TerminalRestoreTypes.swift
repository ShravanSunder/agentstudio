import Foundation

enum BackgroundRestorePolicy: String, Codable, Sendable {
    case off
    case existingSessionsOnly
    case allTerminalPanes
}
