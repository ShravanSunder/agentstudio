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
                        "agentstudio.bridge.lane": "warm",
                        "agentstudio.bridge.phase": "package_apply",
                    ],
                    numericAttributes: [
                        "agentstudio.bridge.content.byte_size_bucket": 100_000
                    ],
                    booleanAttributes: [
                        "agentstudio.bridge.header_supported": true
                    ]
                )
            ]
        )

        let result = validator.validate(batch)

        #expect(result == .accepted(batch))
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
}
