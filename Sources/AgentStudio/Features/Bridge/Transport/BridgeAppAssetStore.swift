import Foundation

struct BridgeAppAsset: Sendable {
    let data: Data
    let mimeType: String
}

actor BridgeAppAssetStore {
    private let appRootURL: URL

    init(
        appRootURL: URL = (Bundle.appResources.resourceURL ?? Bundle.appResources.bundleURL)
            .appendingPathComponent("BridgeWeb/app")
    ) {
        self.appRootURL = appRootURL.standardizedFileURL
    }

    func load(relativePath: String) throws -> BridgeAppAsset {
        let assetURL = appRootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = appRootURL.path
        guard assetURL.path == rootPath || assetURL.path.hasPrefix(rootPath + "/") else {
            throw BridgeSchemeError.invalidRoute(relativePath)
        }

        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            throw BridgeSchemeError.assetNotFound(relativePath)
        }

        return BridgeAppAsset(
            data: try Data(contentsOf: assetURL),
            mimeType: BridgeSchemeHandler.mimeType(for: relativePath)
        )
    }
}
