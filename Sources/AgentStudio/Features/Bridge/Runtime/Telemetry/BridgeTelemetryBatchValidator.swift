import Foundation

enum BridgeTelemetryBatchValidationResult: Equatable, Sendable {
    case accepted(BridgeTelemetryBatch)
    case dropped(BridgeTelemetryDropReason)
}

struct BridgeTelemetryBatchValidator: Sendable {
    private let scopeGate: BridgeTelemetryScopeGate
    private let decoder: JSONDecoder

    init(scopeGate: BridgeTelemetryScopeGate, decoder: JSONDecoder = JSONDecoder()) {
        self.scopeGate = scopeGate
        self.decoder = decoder
    }

    func decodeAndValidate(_ data: Data) -> BridgeTelemetryBatchValidationResult {
        guard data.count <= BridgeTelemetryLimits.maxEncodedBatchBytes else {
            return .dropped(.encodedBatchTooLarge)
        }

        do {
            return try validate(decoder.decode(BridgeTelemetryBatch.self, from: data))
        } catch is BridgeTraceContext.ValidationError {
            return .dropped(.invalidTraceContext)
        } catch {
            return .dropped(.decodingFailed)
        }
    }

    func validate(_ batch: BridgeTelemetryBatch) -> BridgeTelemetryBatchValidationResult {
        guard batch.schemaVersion == 1 else {
            return .dropped(.unsupportedSchemaVersion)
        }
        guard batch.samples.count <= BridgeTelemetryLimits.maxSamplesPerBatch else {
            return .dropped(.tooManySamples)
        }
        guard Self.isSafeControlledString(batch.scenario) else {
            return .dropped(.unsafeAttribute)
        }

        for sample in batch.samples {
            guard sample.scope == .web else {
                return .dropped(.disabledScope)
            }
            guard scopeGate.isEnabled(sample.scope) else {
                return .dropped(.disabledScope)
            }
            guard Self.allowedEventNames.contains(sample.name) else {
                return .dropped(.unsafeEventName)
            }
            if let durationMilliseconds = sample.durationMilliseconds {
                guard durationMilliseconds.isFinite, durationMilliseconds >= 0 else {
                    return .dropped(.invalidDuration)
                }
            }
            guard Self.attributesAreSafe(sample) else {
                return .dropped(.unsafeAttribute)
            }
            guard Self.attributesMatchEventContract(sample) else {
                return .dropped(.unsafeAttribute)
            }
        }

        return .accepted(batch)
    }

    private static func attributesAreSafe(_ sample: BridgeTelemetrySample) -> Bool {
        guard requiredStringAttributeKeys.allSatisfy({ sample.stringAttributes[$0] != nil }) else {
            return false
        }
        for (key, value) in sample.stringAttributes {
            guard allowedStringValuesByAttributeKey[key]?.contains(value) == true else {
                return false
            }
        }
        for (key, value) in sample.numericAttributes {
            guard allowedNumericAttributeKeys.contains(key), value.isFinite else {
                return false
            }
        }
        for key in sample.booleanAttributes.keys {
            guard allowedBooleanAttributeKeys.contains(key) else {
                return false
            }
        }
        return true
    }

    private static func attributesMatchEventContract(_ sample: BridgeTelemetrySample) -> Bool {
        let requiredStringKeys = requiredStringAttributeKeys
        let stringKeys = Set(sample.stringAttributes.keys)
        let numericKeys = Set(sample.numericAttributes.keys)
        let booleanKeys = Set(sample.booleanAttributes.keys)
        guard let phase = sample.stringAttributes["agentstudio.bridge.phase"],
            let plane = BridgeTelemetryPlane(
                rawValue: sample.stringAttributes["agentstudio.bridge.plane"] ?? ""
            ),
            let priority = BridgeTelemetryPriority(
                rawValue: sample.stringAttributes["agentstudio.bridge.priority"] ?? ""
            ),
            let slice = BridgeTelemetrySlice(
                rawValue: sample.stringAttributes["agentstudio.bridge.slice"] ?? ""
            ),
            let transport = sample.stringAttributes["agentstudio.bridge.transport"]
        else {
            return false
        }

        switch sample.name {
        case "performance.bridge.web.content_fetch":
            return phase == "fetch"
                && plane == .data
                && priority == .hot
                && slice == .contentFetch
                && transport == "content"
                && stringKeys
                    == requiredStringKeys.union([
                        "agentstudio.bridge.content.correlation_mode",
                        "agentstudio.bridge.content.role",
                    ])
                && numericKeys.isEmpty
                && booleanKeys == [
                    "agentstudio.bridge.header_missing",
                    "agentstudio.bridge.header_supported",
                ]
        case "performance.bridge.web.first_render":
            return phase == "render"
                && plane == .data
                && priority == .hot
                && pushSliceIsBrowserRenderable(slice)
                && transport == "push"
                && stringKeys == requiredStringKeys
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        case "performance.bridge.web.package_apply":
            return phase == "apply"
                && plane == planeForBrowserPushSlice(slice)
                && priority == priorityForBrowserPushSlice(slice)
                && pushSliceIsBrowserReceivable(slice)
                && transport == "push"
                && stringKeys == requiredStringKeys
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        case "performance.bridge.web.rpc_send":
            return phase == "send"
                && plane == .control
                && priority == .warm
                && slice == .reviewRPC
                && transport == "rpc"
                && stringKeys
                    == requiredStringKeys.union([
                        "agentstudio.bridge.rpc.method_class"
                    ])
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        case "performance.bridge.web.telemetry_drop":
            return phase == "dropped"
                && plane == .observability
                && priority == .bestEffort
                && slice == .telemetryDrop
                && transport == "rpc"
                && stringKeys
                    == requiredStringKeys.union([
                        "agentstudio.bridge.telemetry.drop_reason"
                    ])
                && numericKeys == [
                    "agentstudio.bridge.telemetry.dropped_count"
                ]
                && booleanKeys.isEmpty
        default:
            return false
        }
    }

    private static func pushSliceIsBrowserRenderable(_ slice: BridgeTelemetrySlice) -> Bool {
        switch slice {
        case .diffStatus,
            .diffPackageMetadata,
            .diffPackageDelta,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles:
            true
        case .connectionHealth,
            .commandAcks,
            .reviewRPC,
            .contentFetch,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }

    private static func priorityForBrowserPushSlice(_ slice: BridgeTelemetrySlice) -> BridgeTelemetryPriority {
        switch slice {
        case .diffStatus, .connectionHealth:
            .hot
        case .diffPackageDelta, .reviewThreads, .reviewViewedFiles, .commandAcks:
            .warm
        case .diffPackageMetadata, .diffFiles:
            .cold
        case .reviewRPC:
            .warm
        case .contentFetch,
            .unknown:
            .cold
        case .telemetryBatch, .telemetryIngest, .telemetryDrop:
            .bestEffort
        }
    }

    private static func planeForBrowserPushSlice(_ slice: BridgeTelemetrySlice) -> BridgeTelemetryPlane {
        switch slice {
        case .connectionHealth, .commandAcks, .reviewRPC:
            .control
        case .telemetryBatch, .telemetryIngest, .telemetryDrop:
            .observability
        case .diffStatus,
            .diffPackageMetadata,
            .diffPackageDelta,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .contentFetch,
            .unknown:
            .data
        }
    }

    private static func pushSliceIsBrowserReceivable(_ slice: BridgeTelemetrySlice) -> Bool {
        switch slice {
        case .diffStatus,
            .diffPackageMetadata,
            .diffPackageDelta,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .connectionHealth,
            .commandAcks:
            true
        case .reviewRPC,
            .contentFetch,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }

    private static let requiredStringAttributeKeys: Set<String> = [
        "agentstudio.bridge.phase",
        "agentstudio.bridge.plane",
        "agentstudio.bridge.priority",
        "agentstudio.bridge.slice",
        "agentstudio.bridge.transport",
    ]

    private static let allowedEventNames: Set<String> = [
        "performance.bridge.web.content_fetch",
        "performance.bridge.web.first_render",
        "performance.bridge.web.package_apply",
        "performance.bridge.web.rpc_send",
        "performance.bridge.web.telemetry_drop",
    ]

    private static let allowedStringValuesByAttributeKey: [String: Set<String>] = [
        "agentstudio.bridge.cache.result": [
            "cache_hit",
            "provider_load",
            "in_flight_coalesced",
            "rejected",
        ],
        "agentstudio.bridge.content.correlation_mode": [
            "summary",
            "traceparent",
        ],
        "agentstudio.bridge.content.role": [
            "base",
            "head",
            "diff",
            "file",
            "unknown",
        ],
        "agentstudio.bridge.generation.relation": [
            "current",
            "stale",
            "unknown",
        ],
        "agentstudio.bridge.phase": [
            "accepted",
            "apply",
            "content_register",
            "delta_build",
            "dispatch",
            "dropped",
            "error",
            "fetch",
            "package_apply",
            "package_build",
            "render",
            "send",
            "success",
            "transport",
        ],
        "agentstudio.bridge.plane": Set(
            BridgeTelemetryPlane.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.priority": Set(
            BridgeTelemetryPriority.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.rpc.method_class": [
            "other",
            "review",
            "telemetry",
        ],
        "agentstudio.bridge.slice": Set(
            BridgeTelemetrySlice.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.telemetry.drop_reason": Set(
            BridgeTelemetryDropReason.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.test.scenario": [
            "package_apply_content_fetch_v1"
        ],
        "agentstudio.bridge.transport": [
            "content",
            "push",
            "rpc",
            "swift",
        ],
    ]

    private static let allowedNumericAttributeKeys: Set<String> = [
        "agentstudio.bridge.batch.sample_count",
        "agentstudio.bridge.content.byte_size_bucket",
        "agentstudio.bridge.content.line_count_bucket",
        "agentstudio.bridge.telemetry.dropped_count",
    ]

    private static let allowedBooleanAttributeKeys: Set<String> = [
        "agentstudio.bridge.cache_hit",
        "agentstudio.bridge.content.binary",
        "agentstudio.bridge.content.stale",
        "agentstudio.bridge.header_missing",
        "agentstudio.bridge.header_supported",
    ]

    private static func isSafeControlledString(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
                || scalar == ":"
        }
    }
}
