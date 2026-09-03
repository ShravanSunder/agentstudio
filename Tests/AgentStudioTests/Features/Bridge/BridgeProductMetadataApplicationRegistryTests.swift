import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product metadata application registry")
struct BridgeProductMetadataApplicationRegistryTests {
    @Test("subscription kind is a strict string identity")
    func subscriptionKindIsStrictStringIdentity() throws {
        // Arrange / Act
        let fixtureKind = try BridgeProductSubscriptionKind("fixture.metadata")

        // Assert
        #expect(fixtureKind.rawValue == "fixture.metadata")
        #expect(throws: (any Error).self) {
            _ = try BridgeProductSubscriptionKind("")
        }
        #expect(throws: (any Error).self) {
            _ = try BridgeProductSubscriptionKind("fixture metadata")
        }
        #expect(throws: (any Error).self) {
            _ = try BridgeProductSubscriptionKind("Fixture.metadata")
        }
    }

    @Test("product registry contains exactly the four wire applications")
    func productRegistryContainsFourRegistrations() throws {
        // Arrange
        let registry = BridgeProductMetadataApplicationRegistry.product

        // Act
        let registrations = registry.registrations

        // Assert
        #expect(
            registrations.map(\.kind) == [
                .fileAnnotations,
                .fileMetadata,
                .reviewAnnotations,
                .reviewMetadata,
            ])
        #expect(registrations.map(\.canonicalInterestTag) == [3, 2, 4, 1])
        #expect(registrations.map(\.surface) == [.file, .file, .review, .review])
    }

    @Test("registry rejects duplicates and reports unknown kinds explicitly")
    func registryRejectsDuplicatesAndUnknownKinds() throws {
        // Arrange
        let erasedFixture = AnyBridgeProductMetadataApplicationProtocol(
            FixtureMetadataApplicationProtocol.self
        )

        // Act / Assert
        #expect(throws: BridgeProductMetadataApplicationRegistryError.duplicateKind(.fixtureMetadata)) {
            _ = try BridgeProductMetadataApplicationRegistry(
                registrations: [erasedFixture, erasedFixture]
            )
        }
        let registry = try BridgeProductMetadataApplicationRegistry(registrations: [erasedFixture])
        #expect(throws: BridgeProductMetadataApplicationRegistryError.unknownKind(.fileMetadata)) {
            _ = try registry.registration(for: .fileMetadata)
        }
    }

    @Test("fixture application opens with canonical empty interests")
    func fixtureApplicationOpensWithCanonicalEmptyInterests() throws {
        // Arrange
        let registration = AnyBridgeProductMetadataApplicationProtocol(
            FixtureMetadataApplicationProtocol.self
        )
        let registry = try BridgeProductMetadataApplicationRegistry(registrations: [registration])

        // Act
        let options = try registration.decodeSubscriptionOptions(from: Data("{}".utf8))
        let initialState = try registration.initialInterestState(from: options)
        let canonicalBytes = try registration.canonicalInterestBytes(from: initialState)

        // Assert
        #expect(try registry.registration(for: .fixtureMetadata).kind == .fixtureMetadata)
        #expect(canonicalBytes == Data([1, 9, 0, 0, 0, 0]))
    }

    @Test("registered raw event validation is strict and generation checked")
    func registeredRawEventValidationIsStrictAndGenerationChecked() throws {
        // Arrange
        let registration = AnyBridgeProductMetadataApplicationProtocol(
            FixtureMetadataApplicationProtocol.self
        )
        let validEvent = Data(#"{"generation":7,"value":"accepted"}"#.utf8)
        let malformedEvent = Data(#"{"generation":7,"unknown":true,"value":"accepted"}"#.utf8)

        // Act / Assert
        #expect(try registration.validateEvent(validEvent, frameSourceGeneration: 7) == validEvent)
        #expect(throws: (any Error).self) {
            _ = try registration.validateEvent(malformedEvent, frameSourceGeneration: 7)
        }
        #expect(throws: BridgeProductMetadataApplicationRegistryError.sourceGenerationMismatch) {
            _ = try registration.validateEvent(validEvent, frameSourceGeneration: 8)
        }
    }

    @Test("producer seal rejects a shape-compatible event of the wrong concrete type")
    func producerSealRejectsShapeCompatibleWrongConcreteType() throws {
        // Arrange
        let registration = AnyBridgeProductMetadataApplicationProtocol(
            FixtureMetadataApplicationProtocol.self
        )
        let foreignEvent = ShapeCompatibleFixtureEvent(generation: 7, value: "accepted")

        // Act / Assert
        #expect(throws: BridgeProductMetadataApplicationRegistryError.typeErasureMismatch) {
            _ = try registration.sealEvent(foreignEvent)
        }
    }

    @Test("producer seal derives generation without decoding its typed event")
    func producerSealDerivesGenerationWithoutDecoding() throws {
        // Arrange
        let registration = AnyBridgeProductMetadataApplicationProtocol(
            NonDecodableFixtureMetadataApplicationProtocol.self
        )
        let event = NonDecodableFixtureMetadataApplicationProtocol.Event(
            generation: 9,
            value: "typed"
        )

        // Act
        let sealedEvent = try registration.sealEvent(event)

        // Assert
        #expect(sealedEvent.event == event)
        #expect(sealedEvent.applicationKind == .fixtureMetadata)
        #expect(sealedEvent.sourceGeneration == 9)
        #expect(sealedEvent.encodedApplicationByteCount > 0)
        let encodedPayload = try JSONEncoder.bridgeProductSorted.encode(
            sealedEvent.applicationPayload
        )
        #expect(throws: FixtureMetadataEventDecodeError.self) {
            _ = try registration.validateEvent(encodedPayload, frameSourceGeneration: 9)
        }
    }
}

private struct ShapeCompatibleFixtureEvent: Codable, Equatable, Sendable {
    let generation: Int
    let value: String
}

private struct FixtureMetadataEventDecodeError: Error {}

private enum NonDecodableFixtureMetadataApplicationProtocol:
    BridgeProductMetadataApplicationProtocol
{
    struct SubscriptionOptions: Codable, Equatable, Sendable {}
    struct InterestState: Codable, Equatable, Sendable {}
    struct InterestDelta: Codable, Equatable, Sendable {}

    struct Event: Codable, Equatable, Sendable {
        let generation: Int
        let value: String

        init(generation: Int, value: String) {
            self.generation = generation
            self.value = value
        }

        init(from _: Decoder) throws {
            throw FixtureMetadataEventDecodeError()
        }
    }

    static let kind = BridgeProductSubscriptionKind.fixtureMetadata
    static let surface = BridgeProductSurface.file
    static let canonicalInterestTag: UInt8 = 10
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "non-decodable-fixture"
    )

    static func initialInterestState(from _: SubscriptionOptions) -> InterestState { .init() }
    static func applying(_: [InterestDelta], to state: InterestState) throws -> InterestState { state }
    static func deltaItemCount(_: InterestDelta) -> Int { 0 }
    static func deltaMemberIdentities(_: InterestDelta) -> Set<Data> { [] }
    static func canonicalInterestBody(_: InterestState) throws -> Data { Data() }
    static func sourceGeneration(of event: Event) -> Int { event.generation }
}

private enum FixtureMetadataApplicationProtocol: BridgeProductMetadataApplicationProtocol {
    struct SubscriptionOptions: Codable, Equatable, Sendable {}

    struct InterestState: Codable, Equatable, Sendable {}

    struct InterestDelta: Codable, Equatable, Sendable {}

    struct Event: Codable, Equatable, Sendable {
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case generation
            case value
        }

        let generation: Int
        let value: String

        init(from decoder: Decoder) throws {
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
                contract: "fixture metadata event"
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            generation = try container.decode(Int.self, forKey: .generation)
            value = try container.decode(String.self, forKey: .value)
        }
    }

    static let kind = BridgeProductSubscriptionKind.fixtureMetadata
    static let surface = BridgeProductSurface.file
    static let canonicalInterestTag: UInt8 = 9
    static let telemetryDescriptor = BridgeMetadataApplicationTelemetryDescriptor(
        applicationName: "fixture"
    )

    static func initialInterestState(from _: SubscriptionOptions) -> InterestState { .init() }

    static func applying(
        _: [InterestDelta],
        to state: InterestState
    ) throws -> InterestState { state }

    static func deltaItemCount(_: InterestDelta) -> Int { 0 }

    static func deltaMemberIdentities(_: InterestDelta) -> Set<Data> { [] }

    static func canonicalInterestBody(_: InterestState) throws -> Data {
        Data([0, 0, 0, 0])
    }

    static func sourceGeneration(of event: Event) -> Int { event.generation }
}

extension BridgeProductSubscriptionKind {
    fileprivate static let fixtureMetadata = try! Self("fixture.metadata")
}
