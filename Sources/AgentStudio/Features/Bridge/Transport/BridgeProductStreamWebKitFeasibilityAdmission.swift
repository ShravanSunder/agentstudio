import Foundation

struct BridgeProductStreamWebKitFeasibilityAdmission {
    enum Outcome {
        case accepted(BridgeProductStreamProbeRequestBody, BridgeWebKitRequestAPIObservation)
        case rejected(BridgeWebKitRequestAPIObservation, statusCode: Int)
    }

    private struct Context {
        let request: URLRequest
        let route: String
        let capabilityState: BridgeWebKitCapabilityHeaderState
        let maximumRequestBodyBytes: Int
        let admissionStartedAt: ContinuousClock.Instant
    }

    private struct ObservationDetails {
        let bodySource: BridgeProductRequestBodySource
        let bodyByteCount: Int
        let decodeCallCount: Int
        let providerCallCount: Int
        let bodyBytesExact: Bool
        let outcome: BridgeWebKitAdmissionOutcome
        let decodeDurationMicroseconds: UInt64
        let nearCapMeasurementPhase: BridgeWebKitNearCapMeasurementPhase?
        let nearCapMeasurementIndex: Int?

        init(
            bodySource: BridgeProductRequestBodySource,
            bodyByteCount: Int,
            decodeCallCount: Int,
            providerCallCount: Int,
            bodyBytesExact: Bool,
            outcome: BridgeWebKitAdmissionOutcome,
            decodeDurationMicroseconds: UInt64 = 0,
            nearCapMeasurementPhase: BridgeWebKitNearCapMeasurementPhase? = nil,
            nearCapMeasurementIndex: Int? = nil
        ) {
            self.bodySource = bodySource
            self.bodyByteCount = bodyByteCount
            self.decodeCallCount = decodeCallCount
            self.providerCallCount = providerCallCount
            self.bodyBytesExact = bodyBytesExact
            self.outcome = outcome
            self.decodeDurationMicroseconds = decodeDurationMicroseconds
            self.nearCapMeasurementPhase = nearCapMeasurementPhase
            self.nearCapMeasurementIndex = nearCapMeasurementIndex
        }
    }

    let expectedCapability: String
    let maximumRequestBodyBytes: Int

    func admit(_ request: URLRequest, route: String) -> Outcome {
        let admissionStartedAt = ContinuousClock.now
        let capabilityState = Self.capabilityState(
            request: request,
            expectedCapability: expectedCapability
        )
        let context = Context(
            request: request,
            route: route,
            capabilityState: capabilityState,
            maximumRequestBodyBytes: maximumRequestBodyBytes,
            admissionStartedAt: admissionStartedAt
        )
        guard capabilityState == .matches else {
            let rejection: BridgeProductStreamWebKitFeasibilityRejection =
                capabilityState == .missing ? .missingCapability : .wrongCapability
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: .unread,
                    bodyByteCount: 0,
                    decodeCallCount: 0,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(rejection)
                ),
                statusCode: capabilityState == .missing ? 401 : 403
            )
        }
        guard
            request.value(forHTTPHeaderField: "Content-Type")?.lowercased()
                .hasPrefix("application/json") == true
        else {
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: .unread,
                    bodyByteCount: 0,
                    decodeCallCount: 0,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.unsupportedContentType)
                ),
                statusCode: 415
            )
        }
        return admitBody(
            BridgeProductBoundedRequestBodyReader(
                maximumBytes: maximumRequestBodyBytes
            ).read(request),
            context: context
        )
    }

    private func admitBody(
        _ bodyRead: BridgeProductBoundedRequestBodyRead,
        context: Context
    ) -> Outcome {
        switch bodyRead {
        case .missing:
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: .missing,
                    bodyByteCount: 0,
                    decodeCallCount: 0,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.missingBody)
                ),
                statusCode: 400
            )
        case .invalid(let source, let byteCount):
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: source,
                    bodyByteCount: byteCount,
                    decodeCallCount: 0,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.invalidBody)
                ),
                statusCode: 400
            )
        case .oversized(let source, let observedByteCount):
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: source,
                    bodyByteCount: observedByteCount,
                    decodeCallCount: 0,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.oversizedBody)
                ),
                statusCode: 413
            )
        case .body(let data, let source):
            return admitValidatedBody(data, source: source, context: context)
        }
    }

    private func admitValidatedBody(
        _ data: Data,
        source: BridgeProductRequestBodySource,
        context: Context
    ) -> Outcome {
        do {
            try BridgeProductStrictJSON.validate(data)
        } catch {
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: source,
                    bodyByteCount: data.count,
                    decodeCallCount: 0,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.invalidBody)
                ),
                statusCode: 400
            )
        }
        let decodeStartedAt = ContinuousClock.now
        let decodeResult: Result<BridgeProductStreamProbeRequestBody, Error> = Result {
            try BridgeProductStrictJSON.decode(
                BridgeProductStreamProbeRequestBody.self,
                from: data,
                memberVocabulary: BridgeProductStreamProbeRequestBody.strictJSONMemberVocabulary
            )
        }
        let decodeDurationMicroseconds = Self.microseconds(
            decodeStartedAt.duration(to: ContinuousClock.now)
        )
        guard case .success(let decodedBody) = decodeResult else {
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: source,
                    bodyByteCount: data.count,
                    decodeCallCount: 1,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.invalidBody),
                    decodeDurationMicroseconds: decodeDurationMicroseconds
                ),
                statusCode: 400
            )
        }
        guard decodedBody.matches(route: context.route) else {
            return Self.rejectedAdmission(
                context: context,
                details: ObservationDetails(
                    bodySource: source,
                    bodyByteCount: data.count,
                    decodeCallCount: 1,
                    providerCallCount: 0,
                    bodyBytesExact: false,
                    outcome: .rejected(.routeBodyMismatch),
                    decodeDurationMicroseconds: decodeDurationMicroseconds
                ),
                statusCode: 400
            )
        }
        return .accepted(
            decodedBody,
            Self.observation(
                context: context,
                details: ObservationDetails(
                    bodySource: source,
                    bodyByteCount: data.count,
                    decodeCallCount: 1,
                    providerCallCount: 0,
                    bodyBytesExact: decodedBody.hasCanonicalBytes(data),
                    outcome: .accepted,
                    decodeDurationMicroseconds: decodeDurationMicroseconds,
                    nearCapMeasurementPhase: decodedBody.nearCapMeasurementPhase,
                    nearCapMeasurementIndex: decodedBody.nearCapMeasurementIndex
                )
            )
        )
    }

    private static func observation(
        context: Context,
        details: ObservationDetails
    ) -> BridgeWebKitRequestAPIObservation {
        BridgeWebKitRequestAPIObservation(
            route: context.route,
            method: context.request.httpMethod ?? "missing",
            capabilityHeaderState: context.capabilityState,
            declaredLengthHeaderState: declaredLengthState(
                context.request,
                maximumBytes: context.maximumRequestBodyBytes
            ),
            bodySource: details.bodySource,
            bodyByteCount: details.bodyByteCount,
            decodeCallCount: details.decodeCallCount,
            providerCallCount: details.providerCallCount,
            bodyBytesExact: details.bodyBytesExact,
            admissionOutcome: details.outcome,
            nearCapMeasurementPhase: details.nearCapMeasurementPhase,
            nearCapMeasurementIndex: details.nearCapMeasurementIndex,
            admissionDurationMicroseconds: microseconds(
                context.admissionStartedAt.duration(to: ContinuousClock.now)
            ),
            decodeDurationMicroseconds: details.decodeDurationMicroseconds
        )
    }

    private static func rejectedAdmission(
        context: Context,
        details: ObservationDetails,
        statusCode: Int
    ) -> Outcome {
        .rejected(observation(context: context, details: details), statusCode: statusCode)
    }

    private static func capabilityState(
        request: URLRequest,
        expectedCapability: String
    ) -> BridgeWebKitCapabilityHeaderState {
        guard
            let presented = request.value(
                forHTTPHeaderField: BridgeProductStreamWebKitFeasibilityPolicy.capabilityHeader)
        else { return .missing }
        return capabilitiesMatch(presented, expectedCapability) ? .matches : .mismatch
    }

    private static func declaredLengthState(
        _ request: URLRequest,
        maximumBytes: Int
    ) -> BridgeWebKitDeclaredLengthHeaderState {
        guard let rawLength = request.value(forHTTPHeaderField: "Content-Length") else { return .missing }
        guard !rawLength.isEmpty,
            rawLength.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
            let length = Int(rawLength)
        else { return .invalid }
        return length <= maximumBytes
            ? .withinLimit : .oversized
    }

    private static func microseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        let seconds = max(0, components.seconds)
        let attoseconds = max(0, components.attoseconds)
        return UInt64(seconds) * 1_000_000 + UInt64(attoseconds / 1_000_000_000_000)
    }

    private static func capabilitiesMatch(_ presented: String, _ expected: String) -> Bool {
        var presentedBytes = presented.utf8.makeIterator()
        var difference: UInt8 = 0
        var missingPresentedByte = false
        for expectedByte in expected.utf8 {
            guard let presentedByte = presentedBytes.next() else {
                missingPresentedByte = true
                difference |= expectedByte
                continue
            }
            difference |= presentedByte ^ expectedByte
        }
        let hasAdditionalPresentedByte = presentedBytes.next() != nil
        return !missingPresentedByte && !hasAdditionalPresentedByte && difference == 0
    }
}

enum BridgeProductStreamProbeRequestBody: Decodable, Equatable {
    struct NearCapRequest: Equatable {
        let phase: BridgeWebKitNearCapMeasurementPhase
        let sampleIndex: Int
        let padding: String
    }

    struct WorkerResult: Equatable {
        let workerObservedExactFrames: Bool
        let workerObservedIncrementalFrames: Bool
        let cancellationObserved: Bool
        let nearCapTiming: BridgeWebKitNearCapTimingResult
    }

    private enum Kind: String {
        case workerStarted = "s2a.worker.started"
        case streamOpen = "s2a.stream.open"
        case cancelStreamOpen = "s2a.cancel-stream.open"
        case nearCap = "s2a.near-cap"
        case frameObserved = "s2a.frame.observed"
        case result = "s2a.result"
    }

    private struct Key: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            nil
        }
    }

    case workerStarted
    case streamOpen
    case cancelStreamOpen
    case nearCap(NearCapRequest)
    case frameObserved(BridgeWebKitFeasibilityFrameReceipt)
    case result(WorkerResult)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let kindKey = Key("kind")
        let rawKind = try container.decode(String.self, forKey: kindKey)
        guard let kind = Kind(rawValue: rawKind) else {
            throw DecodingError.dataCorruptedError(forKey: kindKey, in: container, debugDescription: "Unknown kind")
        }
        switch kind {
        case .workerStarted:
            try Self.requireExactKeys(container, ["kind"])
            self = .workerStarted
        case .streamOpen:
            try Self.requireExactKeys(container, ["kind"])
            self = .streamOpen
        case .cancelStreamOpen:
            try Self.requireExactKeys(container, ["kind"])
            self = .cancelStreamOpen
        case .nearCap:
            try Self.requireExactKeys(container, ["kind", "phase", "sampleIndex", "padding"])
            let phaseKey = Key("phase")
            let rawPhase = try container.decode(String.self, forKey: phaseKey)
            guard let phase = BridgeWebKitNearCapMeasurementPhase(rawValue: rawPhase) else {
                throw DecodingError.dataCorruptedError(
                    forKey: phaseKey,
                    in: container,
                    debugDescription: "Unknown near-cap measurement phase"
                )
            }
            let sampleIndexKey = Key("sampleIndex")
            let sampleIndex = try container.decode(Int.self, forKey: sampleIndexKey)
            guard sampleIndex >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: sampleIndexKey,
                    in: container,
                    debugDescription: "Negative near-cap sample index"
                )
            }
            self = .nearCap(
                NearCapRequest(
                    phase: phase,
                    sampleIndex: sampleIndex,
                    padding: try container.decode(String.self, forKey: Key("padding"))
                ))
        case .frameObserved:
            try Self.requireExactKeys(container, ["kind", "stream", "sequence"])
            let streamKey = Key("stream")
            let rawStream = try container.decode(String.self, forKey: streamKey)
            guard let producer = BridgeWebKitFeasibilityProducerKind(workerStreamName: rawStream) else {
                throw DecodingError.dataCorruptedError(
                    forKey: streamKey,
                    in: container,
                    debugDescription: "Unknown stream"
                )
            }
            let sequence = try container.decode(Int.self, forKey: Key("sequence"))
            guard sequence >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: Key("sequence"),
                    in: container,
                    debugDescription: "Negative sequence"
                )
            }
            self = .frameObserved(.init(producer: producer, sequence: sequence))
        case .result:
            try Self.requireExactKeys(
                container,
                [
                    "kind", "workerObservedExactFrames", "workerObservedIncrementalFrames",
                    "cancellationObserved", "nearCapTiming",
                ]
            )
            self = .result(
                WorkerResult(
                    workerObservedExactFrames: try container.decode(
                        Bool.self,
                        forKey: Key("workerObservedExactFrames")
                    ),
                    workerObservedIncrementalFrames: try container.decode(
                        Bool.self,
                        forKey: Key("workerObservedIncrementalFrames")
                    ),
                    cancellationObserved: try container.decode(Bool.self, forKey: Key("cancellationObserved")),
                    nearCapTiming: try Self.decodeNearCapTiming(container)
                ))
        }
    }

    private static func expectedKind(for route: String) -> Kind? {
        switch route {
        case "/worker-started": .workerStarted
        case "/stream", "/missing-capability", "/wrong-capability", "/route-mismatch", "/strict-extra":
            .streamOpen
        case "/near-cap", "/oversized-body": .nearCap
        case "/cancel-stream": .cancelStreamOpen
        case "/observed": .frameObserved
        case "/result": .result
        default: nil
        }
    }

    static func supports(route: String) -> Bool {
        expectedKind(for: route) != nil
    }

    func matches(route: String) -> Bool {
        guard let expectedKind = Self.expectedKind(for: route) else { return false }
        switch (self, expectedKind) {
        case (.workerStarted, .workerStarted), (.streamOpen, .streamOpen),
            (.cancelStreamOpen, .cancelStreamOpen), (.nearCap, .nearCap),
            (.frameObserved, .frameObserved), (.result, .result):
            return true
        default:
            return false
        }
    }

    func hasCanonicalBytes(_ data: Data) -> Bool {
        let expected: String
        switch self {
        case .workerStarted:
            expected = "{\"kind\":\"s2a.worker.started\"}"
        case .streamOpen:
            expected = "{\"kind\":\"s2a.stream.open\"}"
        case .cancelStreamOpen:
            expected = "{\"kind\":\"s2a.cancel-stream.open\"}"
        case .nearCap(let request):
            expected =
                "{\"kind\":\"s2a.near-cap\",\"phase\":\"\(request.phase.rawValue)\",\"sampleIndex\":\(request.sampleIndex),\"padding\":\"\(request.padding)\"}"
        case .frameObserved(let receipt):
            expected =
                "{\"kind\":\"s2a.frame.observed\",\"stream\":\"\(receipt.producer.workerStreamName)\",\"sequence\":\(receipt.sequence)}"
        case .result(let result):
            let timing = result.nearCapTiming
            expected =
                "{\"kind\":\"s2a.result\",\"workerObservedExactFrames\":\(result.workerObservedExactFrames),\"workerObservedIncrementalFrames\":\(result.workerObservedIncrementalFrames),\"cancellationObserved\":\(result.cancellationObserved),\"nearCapTiming\":{\"bodyByteCount\":\(timing.bodyByteCount),\"warmupRequestCount\":\(timing.warmupRequestCount),\"measuredRequestCount\":\(timing.measuredRequestCount),\"workerEncodeDurationsMicroseconds\":[\(timing.workerEncodeDurationsMicroseconds.map(String.init).joined(separator: ","))],\"workerFetchCompletionDurationsMicroseconds\":[\(timing.workerFetchCompletionDurationsMicroseconds.map(String.init).joined(separator: ","))]}}"
        }
        return data == Data(expected.utf8)
    }

    var nearCapMeasurementPhase: BridgeWebKitNearCapMeasurementPhase? {
        guard case .nearCap(let request) = self else { return nil }
        return request.phase
    }

    var nearCapMeasurementIndex: Int? {
        guard case .nearCap(let request) = self else { return nil }
        return request.sampleIndex
    }

    private static func requireExactKeys(
        _ container: KeyedDecodingContainer<Key>,
        _ expectedKeys: Set<String>
    ) throws {
        let actualKeys = Set(container.allKeys.map(\.stringValue))
        guard actualKeys == expectedKeys else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Unexpected request keys")
            )
        }
    }

    private static func decodeNearCapTiming(
        _ container: KeyedDecodingContainer<Key>
    ) throws -> BridgeWebKitNearCapTimingResult {
        let timingKey = Key("nearCapTiming")
        let timing = try container.nestedContainer(keyedBy: Key.self, forKey: timingKey)
        try requireExactKeys(
            timing,
            [
                "bodyByteCount", "warmupRequestCount", "measuredRequestCount",
                "workerEncodeDurationsMicroseconds", "workerFetchCompletionDurationsMicroseconds",
            ]
        )
        let bodyByteCount = try timing.decode(Int.self, forKey: Key("bodyByteCount"))
        let warmupRequestCount = try timing.decode(Int.self, forKey: Key("warmupRequestCount"))
        let measuredRequestCount = try timing.decode(Int.self, forKey: Key("measuredRequestCount"))
        let workerEncodeDurationsMicroseconds = try timing.decode(
            [UInt64].self,
            forKey: Key("workerEncodeDurationsMicroseconds")
        )
        let workerFetchCompletionDurationsMicroseconds = try timing.decode(
            [UInt64].self,
            forKey: Key("workerFetchCompletionDurationsMicroseconds")
        )
        guard bodyByteCount >= 0,
            warmupRequestCount >= 0,
            measuredRequestCount >= 0,
            workerEncodeDurationsMicroseconds.count == measuredRequestCount,
            workerFetchCompletionDurationsMicroseconds.count == measuredRequestCount
        else {
            throw DecodingError.dataCorruptedError(
                forKey: timingKey,
                in: container,
                debugDescription: "Invalid near-cap timing result"
            )
        }
        return BridgeWebKitNearCapTimingResult(
            bodyByteCount: bodyByteCount,
            warmupRequestCount: warmupRequestCount,
            measuredRequestCount: measuredRequestCount,
            workerEncodeDurationsMicroseconds: workerEncodeDurationsMicroseconds,
            workerFetchCompletionDurationsMicroseconds: workerFetchCompletionDurationsMicroseconds
        )
    }
}
