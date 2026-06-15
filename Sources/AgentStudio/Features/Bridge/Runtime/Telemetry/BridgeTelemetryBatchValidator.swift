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
        }

        return .accepted(batch)
    }

    private static func attributesAreSafe(_ sample: BridgeTelemetrySample) -> Bool {
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
        "agentstudio.bridge.lane": [
            "hot",
            "warm",
            "cold",
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
        "agentstudio.bridge.rpc.method_class": [
            "other",
            "review",
            "telemetry",
        ],
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
