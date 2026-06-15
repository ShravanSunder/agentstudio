import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryBatchValidatorTests {
    @Test
    func scopeGateExposesOnlyBrowserOwnedScopesToBridgeWeb() {
        let scopeGate = BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit])

        #expect(scopeGate.browserExposedScopes == [.web])
    }

    @Test
    func validatorAcceptsSafeEnabledSamples() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: 2.5,
                    traceContext: try BridgeTraceContext(
                        traceId: "11111111111111111111111111111111",
                        spanId: "2222222222222222",
                        parentSpanId: nil,
                        sampled: true
                    ),
                    stringAttributes: [
                        "agentstudio.bridge.plane": "data",
                        "agentstudio.bridge.phase": "apply",
                        "agentstudio.bridge.priority": "cold",
                        "agentstudio.bridge.slice": "diff_package_metadata",
                        "agentstudio.bridge.transport": "push",
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        let result = validator.validate(batch)

        #expect(result == .accepted(batch))
    }

    @Test
    func validatorAcceptsContentFetchTelemetryWithContentOnlyAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.content_fetch",
                phase: "fetch",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "content",
                extraStrings: [
                    "agentstudio.bridge.content.correlation_mode": "summary",
                    "agentstudio.bridge.content.role": "head",
                ],
                extraBooleans: [
                    "agentstudio.bridge.header_missing": true,
                    "agentstudio.bridge.header_supported": false,
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsConnectionPushApplyTelemetryAsControlPlane() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.package_apply",
                phase: "apply",
                plane: "control",
                priority: "hot",
                slice: "connection_health",
                transport: "push"
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorRejectsEventInappropriateAuxiliaryAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packageApplyWithRPCClass = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.package_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "push",
                extraStrings: ["agentstudio.bridge.rpc.method_class": "telemetry"]
            )
        )
        let rpcSendWithoutMethodClass = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "control",
                priority: "warm",
                slice: "review_rpc",
                transport: "rpc"
            )
        )
        let telemetryDropWithoutDroppedCount = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "best_effort",
                slice: "telemetry_drop",
                transport: "rpc",
                extraStrings: ["agentstudio.bridge.telemetry.drop_reason": "queue_saturated"]
            )
        )

        #expect(validator.validate(packageApplyWithRPCClass) == .dropped(.unsafeAttribute))
        #expect(validator.validate(rpcSendWithoutMethodClass) == .dropped(.unsafeAttribute))
        #expect(validator.validate(telemetryDropWithoutDroppedCount) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsHistoricalLaneAttribute() {
        let historicalBridgeLane = ["agentstudio", "bridge", "lane"].joined(separator: ".")
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: 2.5,
                    traceContext: nil,
                    stringAttributes: [
                        historicalBridgeLane: "warm",
                        "agentstudio.bridge.phase": "package_apply",
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsSamplesMissingRequiredTaxonomyFields() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.telemetry_drop",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.plane": "observability",
                        "agentstudio.bridge.priority": "best_effort",
                        "agentstudio.bridge.slice": "telemetry_drop",
                        "agentstudio.bridge.telemetry.drop_reason": "queue_saturated",
                    ],
                    numericAttributes: [
                        "agentstudio.bridge.telemetry.dropped_count": 1
                    ],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsSpoofedBrowserTelemetryCombinations() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )

        let telemetryDropAsHot = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "hot",
                slice: "telemetry_drop",
                transport: "rpc",
                extraStrings: ["agentstudio.bridge.telemetry.drop_reason": "queue_saturated"]
            )
        )
        let rpcSendAsObservability = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "observability",
                priority: "best_effort",
                slice: "review_rpc",
                transport: "rpc"
            )
        )
        let contentFetchAsSwift = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.content_fetch",
                phase: "fetch",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "swift"
            )
        )

        #expect(validator.validate(telemetryDropAsHot) == .dropped(.unsafeAttribute))
        #expect(validator.validate(rpcSendAsObservability) == .dropped(.unsafeAttribute))
        #expect(validator.validate(contentFetchAsSwift) == .dropped(.unsafeAttribute))
    }

    @Test
    func dropReasonWireValuesUseSnakeCase() throws {
        #expect(BridgeTelemetryDropReason.queueSaturated.rawValue == "queue_saturated")
        #expect(BridgeTelemetryDropReason.decodingFailed.rawValue == "decoding_failed")

        let decoded = try JSONDecoder().decode(
            BridgeTelemetryDropReason.self,
            from: Data(#""too_many_samples""#.utf8)
        )

        #expect(decoded == .tooManySamples)
    }

    @Test
    func validatorRejectsDisabledScopeWithExplicitDropReason() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.disabledScope))
    }

    @Test
    func validatorRejectsOversizedRawPayloadBeforeDecode() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let data = Data(repeating: 65, count: BridgeTelemetryLimits.maxEncodedBatchBytes + 1)

        #expect(validator.decodeAndValidate(data) == .dropped(.encodedBatchTooLarge))
    }

    @Test
    func validatorRejectsUnknownEventNamesAndAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let unknownEventBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.cmd_550e8400-e29b-41d4-a716-446655440000",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let unsafeAttributeBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.item_id": "private-item-id"
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(unknownEventBatch) == .dropped(.unsafeEventName))
        #expect(validator.validate(unsafeAttributeBatch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsUnknownControlledStringValues() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.package_apply",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "phase_550e8400e29b41d4a716446655440000"
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsBrowserBatchesThatClaimNativeScopesOrEvents() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit])
        )
        let nativeScopeBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .swift,
                    name: "performance.bridge.swift.package_build",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let nativeEventBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.webkit.rpc_response",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(nativeScopeBatch) == .dropped(.disabledScope))
        #expect(validator.validate(nativeEventBatch) == .dropped(.unsafeEventName))
    }

    @Test
    func validatorRejectsTooManySamples() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let samples = Array(
            repeating: BridgeTelemetrySample(
                scope: .web,
                name: "performance.bridge.web.package_apply",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [:],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            count: BridgeTelemetryLimits.maxSamplesPerBatch + 1
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: samples
        )

        #expect(validator.validate(batch) == .dropped(.tooManySamples))
    }

    private struct WebSampleProps {
        let name: String
        let phase: String
        let plane: String
        let priority: String
        let slice: String
        let transport: String
        var extraStrings: [String: String] = [:]
        var extraNumbers: [String: Double] = [:]
        var extraBooleans: [String: Bool] = [:]
    }

    private func batchWithWebSample(_ props: WebSampleProps) -> BridgeTelemetryBatch {
        var stringAttributes = [
            "agentstudio.bridge.phase": props.phase,
            "agentstudio.bridge.plane": props.plane,
            "agentstudio.bridge.priority": props.priority,
            "agentstudio.bridge.slice": props.slice,
            "agentstudio.bridge.transport": props.transport,
        ]
        stringAttributes.merge(props.extraStrings) { _, new in new }
        return BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: props.name,
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: stringAttributes,
                    numericAttributes: props.extraNumbers,
                    booleanAttributes: props.extraBooleans
                )
            ]
        )
    }
}
