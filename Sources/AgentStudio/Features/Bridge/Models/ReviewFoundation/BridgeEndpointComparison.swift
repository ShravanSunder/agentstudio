import Foundation

struct BridgeEndpointComparison: Codable, Equatable, Sendable {
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let changedFiles: [BridgeEndpointChangedFile]
}

struct BridgeEndpointChangedFile: Codable, Equatable, Sendable {
    let fileId: String
    let path: String
    let oldPath: String?
    let changeKind: BridgeFileChangeKind
    let language: String?
    let fileExtension: String?
    let sizeBytes: Int
    let oldContentHash: String?
    let newContentHash: String?
    let contentHashAlgorithm: String
    let oldMode: Int32?
    let newMode: Int32?
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let mimeType: String

    init(
        fileId: String,
        path: String,
        oldPath: String?,
        changeKind: BridgeFileChangeKind,
        language: String?,
        fileExtension: String?,
        sizeBytes: Int,
        oldContentHash: String?,
        newContentHash: String?,
        contentHashAlgorithm: String,
        oldMode: Int32? = nil,
        newMode: Int32? = nil,
        additions: Int,
        deletions: Int,
        isBinary: Bool,
        mimeType: String
    ) {
        self.fileId = fileId
        self.path = path
        self.oldPath = oldPath
        self.changeKind = changeKind
        self.language = language
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.oldContentHash = oldContentHash
        self.newContentHash = newContentHash
        self.contentHashAlgorithm = contentHashAlgorithm
        self.oldMode = oldMode
        self.newMode = newMode
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
        self.mimeType = mimeType
    }

    func isGitlink(role: BridgeContentHandle.Role) -> Bool {
        switch role {
        case .base:
            oldMode == 0o160000
        case .head:
            newMode == 0o160000
        case .file, .diff:
            false
        }
    }
}
