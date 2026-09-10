import Foundation

enum BridgeProductMetadataApplicationRegistryError: Error, Equatable {
    case duplicateKind(BridgeProductSubscriptionKind)
    case sourceGenerationMismatch
    case typeErasureMismatch
    case unknownKind(BridgeProductSubscriptionKind)
}

struct BridgeMetadataApplicationTelemetryDescriptor: Equatable, Sendable {
    let applicationName: String
}

protocol BridgeProductMetadataApplicationProtocol: SendableMetatype {
    associatedtype SubscriptionOptions: Codable, Equatable, Sendable
    associatedtype InterestState: Codable, Equatable, Sendable
    associatedtype InterestDelta: Codable, Equatable, Sendable
    associatedtype Event: Codable, Equatable, Sendable

    static var kind: BridgeProductSubscriptionKind { get }
    static var surface: BridgeProductSurface { get }
    static var canonicalInterestTag: UInt8 { get }
    static var telemetryDescriptor: BridgeMetadataApplicationTelemetryDescriptor { get }

    static func initialInterestState(from options: SubscriptionOptions) throws -> InterestState
    static func applying(_ deltas: [InterestDelta], to state: InterestState) throws -> InterestState
    static func deltaItemCount(_ delta: InterestDelta) -> Int
    static func deltaMemberIdentities(_ delta: InterestDelta) -> Set<Data>
    static func canonicalInterestBody(_ state: InterestState) throws -> Data
    static func canonicalInterestPreflight(_ state: InterestState) -> BridgeProductInterestStateEncodingPreflight
    static func sourceGeneration(of event: Event) -> Int
}

extension BridgeProductMetadataApplicationProtocol {
    static func canonicalInterestPreflight(
        _ state: InterestState
    ) -> BridgeProductInterestStateEncodingPreflight {
        do {
            return .accepted(
                canonicalByteCount: try canonicalInterestBody(state).count + 2,
                visitedTextValueCount: 0
            )
        } catch {
            return .exceedsMaximum(
                canonicalByteCountLowerBound: BridgeProductWireContract.maximumSubscriptionInterestStateBytes + 1,
                maximumCanonicalByteCount: BridgeProductWireContract.maximumSubscriptionInterestStateBytes,
                visitedTextValueCount: 0
            )
        }
    }
}

struct BridgeProductMetadataApplicationValue: Equatable, Sendable {
    let applicationKind: BridgeProductSubscriptionKind
    let encodedValue: Data
}

struct BridgeProductSealedMetadataApplicationEvent<Event>: Equatable, Sendable
where Event: Codable & Equatable & Sendable {
    let event: Event
    let applicationKind: BridgeProductSubscriptionKind
    let applicationPayload: BridgeProductJSONValue
    let sourceGeneration: Int
    let encodedApplicationByteCount: Int

    fileprivate init(
        event: Event,
        applicationKind: BridgeProductSubscriptionKind,
        applicationPayload: BridgeProductJSONValue,
        sourceGeneration: Int,
        encodedApplicationByteCount: Int
    ) {
        self.event = event
        self.applicationKind = applicationKind
        self.applicationPayload = applicationPayload
        self.sourceGeneration = sourceGeneration
        self.encodedApplicationByteCount = encodedApplicationByteCount
    }
}

private struct BridgeProductErasedSealedMetadataApplicationEvent: Sendable {
    let applicationKind: BridgeProductSubscriptionKind
    let applicationPayload: BridgeProductJSONValue
    let sourceGeneration: Int
    let encodedApplicationByteCount: Int
}

struct AnyBridgeProductMetadataApplicationProtocol: Sendable {
    let kind: BridgeProductSubscriptionKind
    let surface: BridgeProductSurface
    let canonicalInterestTag: UInt8
    let telemetryDescriptor: BridgeMetadataApplicationTelemetryDescriptor

    private let applyDeltasClosure:
        @Sendable ([BridgeProductMetadataApplicationValue], BridgeProductMetadataApplicationValue) throws ->
            BridgeProductMetadataApplicationValue
    private let canonicalInterestBodyClosure: @Sendable (BridgeProductMetadataApplicationValue) throws -> Data
    private let canonicalInterestPreflightClosure:
        @Sendable (BridgeProductMetadataApplicationValue) throws -> BridgeProductInterestStateEncodingPreflight
    private let decodeInterestDeltaClosure: @Sendable (Data) throws -> BridgeProductMetadataApplicationValue
    private let decodeInterestStateClosure: @Sendable (Data) throws -> BridgeProductMetadataApplicationValue
    private let decodeSubscriptionOptionsClosure: @Sendable (Data) throws -> BridgeProductMetadataApplicationValue
    private let deltaItemCountClosure: @Sendable (BridgeProductMetadataApplicationValue) throws -> Int
    private let deltaMemberIdentitiesClosure: @Sendable (BridgeProductMetadataApplicationValue) throws -> Set<Data>
    private let initialInterestStateClosure:
        @Sendable (BridgeProductMetadataApplicationValue) throws -> BridgeProductMetadataApplicationValue
    private let sealEventClosure:
        @Sendable (any Encodable & Sendable) throws ->
            BridgeProductErasedSealedMetadataApplicationEvent
    private let sourceGenerationClosure: @Sendable (Data) throws -> Int
    private let validateEventClosure: @Sendable (Data, Int) throws -> Data

    init<TApplication: BridgeProductMetadataApplicationProtocol>(_: TApplication.Type) {
        let applicationKind = TApplication.kind
        self.kind = applicationKind
        self.surface = TApplication.surface
        self.canonicalInterestTag = TApplication.canonicalInterestTag
        self.telemetryDescriptor = TApplication.telemetryDescriptor

        self.decodeSubscriptionOptionsClosure = { encodedOptions in
            let options = try Self.decoder.decode(TApplication.SubscriptionOptions.self, from: encodedOptions)
            return try Self.encode(options, applicationKind: applicationKind)
        }
        self.initialInterestStateClosure = { erasedOptions in
            let options: TApplication.SubscriptionOptions = try Self.decode(
                erasedOptions,
                expectedApplicationKind: applicationKind
            )
            return try Self.encode(
                TApplication.initialInterestState(from: options),
                applicationKind: applicationKind
            )
        }
        self.decodeInterestDeltaClosure = { encodedDelta in
            let delta = try Self.decoder.decode(TApplication.InterestDelta.self, from: encodedDelta)
            return try Self.encode(delta, applicationKind: applicationKind)
        }
        self.decodeInterestStateClosure = { encodedState in
            let state = try Self.decoder.decode(TApplication.InterestState.self, from: encodedState)
            return try Self.encode(state, applicationKind: applicationKind)
        }
        self.deltaItemCountClosure = { erasedDelta in
            let delta: TApplication.InterestDelta = try Self.decode(
                erasedDelta,
                expectedApplicationKind: applicationKind
            )
            return TApplication.deltaItemCount(delta)
        }
        self.deltaMemberIdentitiesClosure = { erasedDelta in
            let delta: TApplication.InterestDelta = try Self.decode(
                erasedDelta,
                expectedApplicationKind: applicationKind
            )
            return TApplication.deltaMemberIdentities(delta)
        }
        self.applyDeltasClosure = { erasedDeltas, erasedState in
            let state: TApplication.InterestState = try Self.decode(
                erasedState,
                expectedApplicationKind: applicationKind
            )
            let deltas: [TApplication.InterestDelta] = try erasedDeltas.map {
                try Self.decode($0, expectedApplicationKind: applicationKind)
            }
            return try Self.encode(
                TApplication.applying(deltas, to: state),
                applicationKind: applicationKind
            )
        }
        self.canonicalInterestBodyClosure = { erasedState in
            let state: TApplication.InterestState = try Self.decode(
                erasedState,
                expectedApplicationKind: applicationKind
            )
            return try TApplication.canonicalInterestBody(state)
        }
        self.canonicalInterestPreflightClosure = { erasedState in
            let state: TApplication.InterestState = try Self.decode(
                erasedState,
                expectedApplicationKind: applicationKind
            )
            return TApplication.canonicalInterestPreflight(state)
        }
        self.validateEventClosure = { encodedEvent, frameSourceGeneration in
            let event = try Self.decoder.decode(TApplication.Event.self, from: encodedEvent)
            guard TApplication.sourceGeneration(of: event) == frameSourceGeneration else {
                throw BridgeProductMetadataApplicationRegistryError.sourceGenerationMismatch
            }
            return encodedEvent
        }
        self.sourceGenerationClosure = { encodedEvent in
            let event = try Self.decoder.decode(TApplication.Event.self, from: encodedEvent)
            return TApplication.sourceGeneration(of: event)
        }
        self.sealEventClosure = { candidate in
            guard let event = candidate as? TApplication.Event else {
                throw BridgeProductMetadataApplicationRegistryError.typeErasureMismatch
            }
            let encodedEvent = try Self.encoder.encode(event)
            return BridgeProductErasedSealedMetadataApplicationEvent(
                applicationKind: applicationKind,
                applicationPayload: try Self.decoder.decode(
                    BridgeProductJSONValue.self,
                    from: encodedEvent
                ),
                sourceGeneration: TApplication.sourceGeneration(of: event),
                encodedApplicationByteCount: encodedEvent.count
            )
        }
    }

    func decodeSubscriptionOptions(from encodedOptions: Data) throws -> BridgeProductMetadataApplicationValue {
        try decodeSubscriptionOptionsClosure(encodedOptions)
    }

    func initialInterestState(
        from options: BridgeProductMetadataApplicationValue
    ) throws -> BridgeProductMetadataApplicationValue {
        try initialInterestStateClosure(options)
    }

    func decodeInterestDelta(from encodedDelta: Data) throws -> BridgeProductMetadataApplicationValue {
        try decodeInterestDeltaClosure(encodedDelta)
    }

    func decodeInterestState(from encodedState: Data) throws -> BridgeProductMetadataApplicationValue {
        try decodeInterestStateClosure(encodedState)
    }

    func deltaItemCount(_ delta: BridgeProductMetadataApplicationValue) throws -> Int {
        try deltaItemCountClosure(delta)
    }

    func deltaMemberIdentities(
        _ delta: BridgeProductMetadataApplicationValue
    ) throws -> Set<Data> {
        try deltaMemberIdentitiesClosure(delta)
    }

    func applying(
        _ deltas: [BridgeProductMetadataApplicationValue],
        to state: BridgeProductMetadataApplicationValue
    ) throws -> BridgeProductMetadataApplicationValue {
        try applyDeltasClosure(deltas, state)
    }

    func canonicalInterestBytes(
        from state: BridgeProductMetadataApplicationValue
    ) throws -> Data {
        var encoded = Data([1, canonicalInterestTag])
        encoded.append(try canonicalInterestBodyClosure(state))
        return encoded
    }

    func canonicalInterestPreflight(
        _ state: BridgeProductMetadataApplicationValue
    ) throws -> BridgeProductInterestStateEncodingPreflight {
        try canonicalInterestPreflightClosure(state)
    }

    func validateEvent(_ encodedEvent: Data, frameSourceGeneration: Int) throws -> Data {
        try validateEventClosure(encodedEvent, frameSourceGeneration)
    }

    func sourceGeneration(of encodedEvent: Data) throws -> Int {
        try sourceGenerationClosure(encodedEvent)
    }

    func sealEvent<Event>(_ event: Event) throws -> BridgeProductSealedMetadataApplicationEvent<Event>
    where Event: Codable & Equatable & Sendable {
        let sealedEvent = try sealEventClosure(event)
        return BridgeProductSealedMetadataApplicationEvent(
            event: event,
            applicationKind: sealedEvent.applicationKind,
            applicationPayload: sealedEvent.applicationPayload,
            sourceGeneration: sealedEvent.sourceGeneration,
            encodedApplicationByteCount: sealedEvent.encodedApplicationByteCount
        )
    }

    func decodeEvent<TEvent: Decodable>(
        _ eventType: TEvent.Type,
        from payload: BridgeProductJSONValue
    ) throws -> TEvent {
        let encodedEvent = try Self.encoder.encode(payload)
        _ = try sourceGenerationClosure(encodedEvent)
        return try Self.decoder.decode(eventType, from: encodedEvent)
    }

    private static var decoder: JSONDecoder { JSONDecoder() }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func encode<TValue: Encodable>(
        _ value: TValue,
        applicationKind: BridgeProductSubscriptionKind
    ) throws -> BridgeProductMetadataApplicationValue {
        BridgeProductMetadataApplicationValue(
            applicationKind: applicationKind,
            encodedValue: try encoder.encode(value)
        )
    }

    private static func decode<TValue: Decodable>(
        _ value: BridgeProductMetadataApplicationValue,
        expectedApplicationKind: BridgeProductSubscriptionKind
    ) throws -> TValue {
        guard value.applicationKind == expectedApplicationKind else {
            throw BridgeProductMetadataApplicationRegistryError.typeErasureMismatch
        }
        return try decoder.decode(TValue.self, from: value.encodedValue)
    }
}

struct BridgeProductMetadataApplicationRegistry: Sendable {
    let registrations: [AnyBridgeProductMetadataApplicationProtocol]
    private let registrationByKind: [BridgeProductSubscriptionKind: AnyBridgeProductMetadataApplicationProtocol]

    init(registrations: [AnyBridgeProductMetadataApplicationProtocol]) throws {
        var registrationByKind: [BridgeProductSubscriptionKind: AnyBridgeProductMetadataApplicationProtocol] = [:]
        for registration in registrations {
            guard registrationByKind[registration.kind] == nil else {
                throw BridgeProductMetadataApplicationRegistryError.duplicateKind(registration.kind)
            }
            registrationByKind[registration.kind] = registration
        }
        self.registrations = registrations
        self.registrationByKind = registrationByKind
    }

    func registration(
        for kind: BridgeProductSubscriptionKind
    ) throws -> AnyBridgeProductMetadataApplicationProtocol {
        guard let registration = registrationByKind[kind] else {
            throw BridgeProductMetadataApplicationRegistryError.unknownKind(kind)
        }
        return registration
    }
}

struct BridgeProductEmptySubscriptionOptions: Codable, Equatable, Sendable {
    init() {}

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [],
            contract: "empty subscription options"
        )
        self.init()
    }
}

struct BridgeProductAnnotationInterestState: Codable, Equatable, Sendable {
    init() {}

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [],
            contract: "annotation interest state"
        )
        self.init()
    }
}

struct BridgeProductFileMetadataSubscriptionOptions: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case source }

    let source: BridgeProductFileSourceSpec

    init(source: BridgeProductFileSourceSpec) { self.source = source }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file metadata subscription options"
        )
        source = try decoder.container(keyedBy: CodingKeys.self).decode(
            BridgeProductFileSourceSpec.self,
            forKey: .source
        )
    }
}

struct BridgeProductFileMetadataInterestState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case interests, pathScope }

    let interests: [BridgeProductFileMetadataInterestStateGroup]
    let pathScope: [String]

    init(interests: [BridgeProductFileMetadataInterestStateGroup], pathScope: [String]) {
        self.interests = interests
        self.pathScope = pathScope
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file metadata interest state"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interests = try container.decode([BridgeProductFileMetadataInterestStateGroup].self, forKey: .interests)
        pathScope = try container.decode([String].self, forKey: .pathScope)
    }
}

struct BridgeProductReviewMetadataInterestState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case interests }

    let interests: [BridgeProductReviewMetadataInterestStateGroup]

    init(interests: [BridgeProductReviewMetadataInterestStateGroup]) { self.interests = interests }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review metadata interest state"
        )
        interests = try decoder.container(keyedBy: CodingKeys.self).decode(
            [BridgeProductReviewMetadataInterestStateGroup].self,
            forKey: .interests
        )
    }
}

enum BridgeProductFileAnnotationsMetadataApplication: BridgeProductMetadataApplicationProtocol {
    typealias SubscriptionOptions = BridgeProductEmptySubscriptionOptions
    typealias InterestState = BridgeProductAnnotationInterestState
    typealias InterestDelta = BridgeProductAnnotationInterestDelta
    typealias Event = BridgeProductWorktreeAnnotationEvent

    static let kind = BridgeProductSubscriptionKind.fileAnnotations
    static let surface = BridgeProductSurface.file
    static let canonicalInterestTag: UInt8 = 3
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "worktree-annotations"
    )

    static func initialInterestState(from _: SubscriptionOptions) -> InterestState { .init() }
    static func applying(_: [InterestDelta], to state: InterestState) -> InterestState { state }
    static func deltaItemCount(_: InterestDelta) -> Int { 0 }
    static func deltaMemberIdentities(_: InterestDelta) -> Set<Data> { [] }
    static func canonicalInterestBody(_: InterestState) -> Data { Data([0, 0, 0, 0]) }
    static func sourceGeneration(of event: Event) -> Int { event.sourceGeneration }
}

enum BridgeProductFileMetadataApplication: BridgeProductMetadataApplicationProtocol {
    typealias SubscriptionOptions = BridgeProductFileMetadataSubscriptionOptions
    typealias InterestState = BridgeProductFileMetadataInterestState
    typealias InterestDelta = BridgeProductFileMetadataInterestDelta
    typealias Event = BridgeProductFileMetadataEvent

    static let kind = BridgeProductSubscriptionKind.fileMetadata
    static let surface = BridgeProductSurface.file
    static let canonicalInterestTag: UInt8 = 2
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "worktree-file"
    )

    static func initialInterestState(from _: SubscriptionOptions) -> InterestState {
        .init(interests: [], pathScope: [])
    }

    static func applying(_ deltas: [InterestDelta], to state: InterestState) throws -> InterestState {
        try BridgeProductRegisteredInterestMutation.applyFileMetadata(
            deltas,
            to: state
        )
    }

    static func deltaItemCount(_ delta: InterestDelta) -> Int {
        delta.add.count + delta.addPathScope.count + delta.removePathScope.count + delta.removePaths.count
    }

    static func deltaMemberIdentities(_ delta: InterestDelta) -> Set<Data> {
        let addedPaths = delta.add.map { Data([1]) + Data($0.path.utf8) }
        let removedPaths = delta.removePaths.map { Data([1]) + Data($0.utf8) }
        let addedScopes = delta.addPathScope.map { Data([2]) + Data($0.utf8) }
        let removedScopes = delta.removePathScope.map { Data([2]) + Data($0.utf8) }
        return Set(addedPaths + removedPaths + addedScopes + removedScopes)
    }

    static func canonicalInterestBody(_ state: InterestState) throws -> Data {
        try BridgeProductInterestStateCanonicalCodec.fileMetadataBody(
            interests: state.interests,
            pathScope: state.pathScope
        )
    }

    static func canonicalInterestPreflight(
        _ state: InterestState
    ) -> BridgeProductInterestStateEncodingPreflight {
        BridgeProductInterestStateCanonicalCodec.fileMetadataPreflight(
            interests: state.interests,
            pathScope: state.pathScope
        )
    }

    static func sourceGeneration(of event: Event) -> Int { event.sourceGeneration }
}

enum BridgeProductReviewAnnotationsMetadataApplication: BridgeProductMetadataApplicationProtocol {
    typealias SubscriptionOptions = BridgeProductEmptySubscriptionOptions
    typealias InterestState = BridgeProductAnnotationInterestState
    typealias InterestDelta = BridgeProductAnnotationInterestDelta
    typealias Event = BridgeProductWorktreeAnnotationEvent

    static let kind = BridgeProductSubscriptionKind.reviewAnnotations
    static let surface = BridgeProductSurface.review
    static let canonicalInterestTag: UInt8 = 4
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "worktree-annotations"
    )

    static func initialInterestState(from _: SubscriptionOptions) -> InterestState { .init() }
    static func applying(_: [InterestDelta], to state: InterestState) -> InterestState { state }
    static func deltaItemCount(_: InterestDelta) -> Int { 0 }
    static func deltaMemberIdentities(_: InterestDelta) -> Set<Data> { [] }
    static func canonicalInterestBody(_: InterestState) -> Data { Data([0, 0, 0, 0]) }
    static func sourceGeneration(of event: Event) -> Int { event.sourceGeneration }
}

enum BridgeProductReviewMetadataApplication: BridgeProductMetadataApplicationProtocol {
    typealias SubscriptionOptions = BridgeProductEmptySubscriptionOptions
    typealias InterestState = BridgeProductReviewMetadataInterestState
    typealias InterestDelta = BridgeProductReviewMetadataInterestDelta
    typealias Event = BridgeProductReviewMetadataEvent

    static let kind = BridgeProductSubscriptionKind.reviewMetadata
    static let surface = BridgeProductSurface.review
    static let canonicalInterestTag: UInt8 = 1
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "review"
    )

    static func initialInterestState(from _: SubscriptionOptions) -> InterestState {
        .init(interests: [])
    }

    static func applying(_ deltas: [InterestDelta], to state: InterestState) throws -> InterestState {
        try BridgeProductRegisteredInterestMutation.applyReviewMetadata(deltas, to: state)
    }

    static func deltaItemCount(_ delta: InterestDelta) -> Int {
        delta.add.count + delta.removeItemIds.count
    }

    static func deltaMemberIdentities(_ delta: InterestDelta) -> Set<Data> {
        Set(
            delta.add.map { Data([0]) + Data($0.itemId.utf8) }
                + delta.removeItemIds.map { Data([0]) + Data($0.utf8) }
        )
    }

    static func canonicalInterestBody(_ state: InterestState) throws -> Data {
        try BridgeProductInterestStateCanonicalCodec.reviewMetadataBody(interests: state.interests)
    }

    static func canonicalInterestPreflight(
        _ state: InterestState
    ) -> BridgeProductInterestStateEncodingPreflight {
        BridgeProductInterestStateCanonicalCodec.reviewMetadataPreflight(interests: state.interests)
    }

    static func sourceGeneration(of event: Event) -> Int { event.generation }
}

private enum BridgeProductRegisteredInterestMutation {
    private struct InterestMember: Sendable {
        let value: String
        let lane: BridgeProductDemandLane
    }

    private static let demandLaneOrder: [BridgeProductDemandLane] = [
        .foreground, .active, .visible, .nearby, .speculative, .idle,
    ]

    static func applyFileMetadata(
        _ deltas: [BridgeProductFileMetadataInterestDelta],
        to state: BridgeProductFileMetadataInterestState
    ) throws -> BridgeProductFileMetadataInterestState {
        var members = fileInterestMembers(from: state.interests)
        var scopedPaths = Dictionary(
            uniqueKeysWithValues: state.pathScope.map {
                (Data($0.utf8), $0)
            }
        )
        for delta in deltas {
            for addition in delta.add {
                members[Data(addition.path.utf8)] = .init(value: addition.path, lane: addition.lane)
            }
            for path in delta.removePaths { members.removeValue(forKey: Data(path.utf8)) }
            for path in delta.addPathScope { scopedPaths[Data(path.utf8)] = path }
            for path in delta.removePathScope { scopedPaths.removeValue(forKey: Data(path.utf8)) }
        }
        let orderedPathScope =
            scopedPaths
            .map { (identity: $0.key, path: $0.value) }
            .sorted { $0.identity.lexicographicallyPrecedes($1.identity) }
            .map(\.path)
        return .init(
            interests: try demandLaneOrder.compactMap { lane in
                let values = orderedValues(in: members, lane: lane)
                return values.isEmpty ? nil : try .init(lane: lane, paths: values)
            },
            pathScope: orderedPathScope
        )
    }

    static func applyReviewMetadata(
        _ deltas: [BridgeProductReviewMetadataInterestDelta],
        to state: BridgeProductReviewMetadataInterestState
    ) throws -> BridgeProductReviewMetadataInterestState {
        var members = reviewInterestMembers(from: state.interests)
        for delta in deltas {
            for addition in delta.add {
                members[Data(addition.itemId.utf8)] = .init(value: addition.itemId, lane: addition.lane)
            }
            for itemId in delta.removeItemIds { members.removeValue(forKey: Data(itemId.utf8)) }
        }
        return .init(
            interests: try demandLaneOrder.compactMap { lane in
                let values = orderedValues(in: members, lane: lane)
                return values.isEmpty ? nil : try .init(itemIds: values, lane: lane)
            }
        )
    }

    private static func fileInterestMembers(
        from groups: [BridgeProductFileMetadataInterestStateGroup]
    ) -> [Data: InterestMember] {
        Dictionary(
            uniqueKeysWithValues: groups.flatMap { group in
                group.paths.map { (Data($0.utf8), .init(value: $0, lane: group.lane)) }
            })
    }

    private static func reviewInterestMembers(
        from groups: [BridgeProductReviewMetadataInterestStateGroup]
    ) -> [Data: InterestMember] {
        Dictionary(
            uniqueKeysWithValues: groups.flatMap { group in
                group.itemIds.map { (Data($0.utf8), .init(value: $0, lane: group.lane)) }
            })
    }

    private static func orderedValues(
        in members: [Data: InterestMember],
        lane: BridgeProductDemandLane
    ) -> [String] {
        members
            .filter { $0.value.lane == lane }
            .map { (identity: $0.key, value: $0.value.value) }
            .sorted { $0.identity.lexicographicallyPrecedes($1.identity) }
            .map(\.value)
    }
}
