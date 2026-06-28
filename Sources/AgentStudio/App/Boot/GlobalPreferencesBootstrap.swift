import Foundation

enum GlobalPreferencesBootstrap {
    static let defaultMaximumFileSizeBytes: UInt64 = 64 * 1024

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        releaseChannel: AppDataPaths.ReleaseChannel = .current,
        isDebugBuild: Bool = AppDataPaths.isDebugBuild,
        maximumFileSizeBytes: UInt64 = Self.defaultMaximumFileSizeBytes,
        fileManager: FileManager = .default
    ) -> GlobalPreferencesLoadResult {
        let startedNanoseconds = DispatchTime.now().uptimeNanoseconds
        func result(_ status: GlobalPreferencesLoadStatus) -> GlobalPreferencesLoadResult {
            GlobalPreferencesLoadResult(
                status: status,
                elapsedMilliseconds: Self.elapsedMillisecondsSince(startedNanoseconds)
            )
        }

        let preferencesURL = AppDataPaths.globalPreferencesURL(
            environment: environment,
            releaseChannel: releaseChannel,
            isDebugBuild: isDebugBuild
        )

        do {
            guard try preferencesFileExists(at: preferencesURL, fileManager: fileManager) else {
                return result(.missing)
            }

            let resourceValues = try preferencesURL.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize, UInt64(fileSize) > maximumFileSizeBytes {
                return result(
                    .invalidOversized(
                        byteCount: UInt64(fileSize),
                        maximumBytes: maximumFileSizeBytes
                    )
                )
            }

            let data = try readPreferencesData(
                at: preferencesURL,
                maximumFileSizeBytes: maximumFileSizeBytes
            )
            if UInt64(data.count) > maximumFileSizeBytes {
                return result(
                    .invalidOversized(
                        byteCount: UInt64(data.count),
                        maximumBytes: maximumFileSizeBytes
                    )
                )
            }

            if let invalidField = invalidPreferenceField(in: data) {
                return result(.invalidField(invalidField))
            }

            let payload: GlobalPreferencesPayload
            do {
                payload = try JSONDecoder().decode(GlobalPreferencesPayload.self, from: data)
            } catch {
                return result(.invalidMalformedJSON)
            }

            guard payload.schemaVersion == 1 else {
                return result(.invalidUnsupportedSchema(schemaVersion: payload.schemaVersion))
            }

            let preferences = payload.observability.preferences()
            if let rejectedEndpoint = AgentStudioTracePreferenceLayer.rejectedOTLPEndpointSelector(
                preferences.otlpEndpoint)
            {
                return result(.invalidEndpoint(rejectedEndpoint))
            }

            return result(.loaded(preferences))
        } catch {
            return result(.readFailed)
        }
    }

    private static func invalidPreferenceField(in data: Data) -> String? {
        guard
            let rootObject = try? JSONSerialization.jsonObject(with: data),
            let root = rootObject as? [String: Any]
        else { return nil }

        let allowedRootKeys: Set<String> = ["schemaVersion", "observability"]
        if let unknownRootKey = root.keys.first(where: { !allowedRootKeys.contains($0) }) {
            return unknownRootKey
        }

        guard let observability = root["observability"] as? [String: Any] else {
            return nil
        }
        let allowedObservabilityKeys: Set<String> = [
            "enabled",
            "traceTags",
            "traceBackend",
            "traceFlush",
            "otlpEndpoint",
        ]
        if let unknownObservabilityKey = observability.keys.first(where: { !allowedObservabilityKeys.contains($0) }) {
            return "observability.\(unknownObservabilityKey)"
        }

        return AgentStudioTracePreferenceLayer.invalidSemanticField(in: observability)
    }

    private static func preferencesFileExists(at url: URL, fileManager: FileManager) throws -> Bool {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return !isDirectory.boolValue
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues?.isSymbolicLink == true {
            return true
        }

        return false
    }

    private static func readPreferencesData(
        at url: URL,
        maximumFileSizeBytes: UInt64
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        let readLimit = Int(min(maximumFileSizeBytes + 1, UInt64(Int.max)))
        return try handle.read(upToCount: readLimit) ?? Data()
    }

    private static func elapsedMillisecondsSince(_ startedNanoseconds: UInt64) -> Double {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedNanoseconds
        return Double(elapsedNanoseconds) / 1_000_000
    }
}

struct GlobalPreferencesLoadResult: Equatable, Sendable {
    let status: GlobalPreferencesLoadStatus
    let elapsedMilliseconds: Double

    init(status: GlobalPreferencesLoadStatus, elapsedMilliseconds: Double = 0) {
        self.status = status
        self.elapsedMilliseconds = elapsedMilliseconds
    }

    var tracePreferenceLayer: AgentStudioTracePreferenceLayer? {
        guard case .loaded(let preferences) = status else { return nil }
        return AgentStudioTracePreferenceLayer(
            enabled: preferences.enabled,
            traceTags: preferences.traceTags,
            traceBackend: preferences.traceBackend,
            traceFlush: preferences.traceFlush,
            otlpEndpoint: preferences.otlpEndpoint
        )
    }
}

enum GlobalPreferencesLoadStatus: Equatable, Sendable {
    case missing
    case loaded(GlobalObservabilityPreferences)
    case invalidMalformedJSON
    case invalidUnsupportedSchema(schemaVersion: Int)
    case invalidOversized(byteCount: UInt64, maximumBytes: UInt64)
    case invalidField(String)
    case invalidEndpoint(String)
    case readFailed
}
