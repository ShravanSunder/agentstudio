import AgentStudioCore
import Foundation

/// Why an exact file could not be admitted as an opened document. Each case is
/// specific so a caller never receives an unrelated fallback destination (R1).
enum BridgeDocumentAdmissionRefusal: Error, Equatable, Sendable {
    /// A relative path arrived without the caller's captured base directory.
    case relativePathWithoutBaseDirectory
    case notFound
    /// A directory, device, pipe or other non-regular filesystem object.
    case notRegularFile
    case unreadable
    case unsupportedContent(BridgeDocumentUnsupportedContent)
}

enum BridgeDocumentUnsupportedContent: Equatable, Sendable {
    case binary
    case unsupportedEncoding
    case tooLarge
}

struct BridgeDocumentAdmissionRequest: Equatable, Sendable {
    let requestedPath: String
    /// The caller's CWD captured when the request was made; a relative path is
    /// never reinterpreted against later focus or CWD.
    let baseDirectory: URL?
}

struct BridgeAdmittedDocument: Equatable, Sendable {
    let location: BridgeDocumentLocation
    let byteCount: Int
}

/// Admits one exact local file as a document a receiver may display.
///
/// Admission authorizes that file only: it never enumerates the containing
/// directory, registers a repository or invents a worktree identity (R14).
/// Supported content is decided by the same reader and scan that later issue
/// content descriptors.
enum BridgeDocumentAdmission {
    @concurrent
    static func admit(
        _ request: BridgeDocumentAdmissionRequest
    ) async -> Result<BridgeAdmittedDocument, BridgeDocumentAdmissionRefusal> {
        let requestedURL: URL
        if request.requestedPath.hasPrefix("/") {
            requestedURL = URL(fileURLWithPath: request.requestedPath)
        } else if let baseDirectory = request.baseDirectory {
            requestedURL = baseDirectory.appending(path: request.requestedPath)
        } else {
            return .failure(.relativePathWithoutBaseDirectory)
        }
        let canonicalURL = DarwinFSEventPathCanonicalizer.canonicalURL(
            requestedURL.standardizedFileURL
        )
        guard let location = BridgeDocumentLocation(canonicalPath: canonicalURL.path) else {
            return .failure(.notRegularFile)
        }
        if let presenceRefusal = presenceRefusal(for: location) {
            return .failure(presenceRefusal)
        }
        let classification: BridgePaneProductFileContentClassification
        do {
            classification = try await BridgePaneProductFileContentSource.classifyContent(
                rootURL: location.fileURL.deletingLastPathComponent(),
                relativePath: location.displayName
            )
        } catch BridgeSourcePathContainmentError.notRegularFile {
            return .failure(.notRegularFile)
        } catch {
            // The file can disappear or be replaced between the presence check
            // and the read; report what is true now rather than a stale success.
            return .failure(presenceRefusal(for: location) ?? .unreadable)
        }
        switch classification {
        case .supported(let byteCount):
            return .success(BridgeAdmittedDocument(location: location, byteCount: byteCount))
        case .binary:
            return .failure(.unsupportedContent(.binary))
        case .unsupportedEncoding:
            return .failure(.unsupportedContent(.unsupportedEncoding))
        case .tooLarge:
            return .failure(.unsupportedContent(.tooLarge))
        }
    }

    private static func presenceRefusal(
        for location: BridgeDocumentLocation
    ) -> BridgeDocumentAdmissionRefusal? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.canonicalPath, isDirectory: &isDirectory)
        else {
            return .notFound
        }
        return isDirectory.boolValue ? .notRegularFile : nil
    }
}

/// Canonicalizes a command's absolute document path off the MainActor so it
/// matches the receiver's admitted locations. It admits nothing.
package enum BridgeDocumentLocationCanonicalizer {
    @concurrent
    package static func canonicalLocation(ofAbsolutePath path: String) async -> BridgeDocumentLocation? {
        guard path.hasPrefix("/") else { return nil }
        let canonicalURL = DarwinFSEventPathCanonicalizer.canonicalURL(
            URL(fileURLWithPath: path).standardizedFileURL
        )
        return BridgeDocumentLocation(canonicalPath: canonicalURL.path)
    }
}
