import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

public enum IPCEventDeliveryResult: Equatable, Sendable {
    case delivered
    case backpressure
}

public protocol IPCEventSubscriber: Sendable {
    func deliver(_ frame: String) async throws -> IPCEventDeliveryResult
}

public struct IPCEventBrokerError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case emptyEventSet
        case unsupportedEventName
        case subscriptionNotFound
        case reservedInboundNotification
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

public struct IPCEventDeliveryFailure: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case backpressure
        case deliveryFailed
    }

    public let subscriptionId: UUID
    public let reason: Reason

    public init(subscriptionId: UUID, reason: Reason) {
        self.subscriptionId = subscriptionId
        self.reason = reason
    }
}

public actor IPCEventBroker {
    private struct Subscription: Sendable {
        let id: UUID
        let principal: IPCPrincipal
        let connectionId: UUID
        let eventNames: Set<IPCEventName>
        let subscriber: any IPCEventSubscriber
    }

    private var subscriptionsById: [UUID: Subscription] = [:]
    private let allowedEventNames: Set<IPCEventName>
    private let makeSubscriptionId: @Sendable () -> UUID

    public init(
        allowedEventNames: Set<IPCEventName> = Set(IPCEventName.allCases),
        makeSubscriptionId: (@Sendable () -> UUID)? = nil
    ) {
        self.allowedEventNames = allowedEventNames
        self.makeSubscriptionId = makeSubscriptionId ?? { UUIDv7.generate() }
    }

    public func subscribe(
        eventNames requestedEventNames: Set<IPCEventName>,
        principal: IPCPrincipal,
        connectionId: UUID,
        subscriber: any IPCEventSubscriber
    ) throws -> IPCEventSubscriptionResult {
        guard !requestedEventNames.isEmpty else {
            throw IPCEventBrokerError(reason: .emptyEventSet)
        }
        guard requestedEventNames.isSubset(of: allowedEventNames) else {
            throw IPCEventBrokerError(reason: .unsupportedEventName)
        }

        let subscriptionId = makeSubscriptionId()
        subscriptionsById[subscriptionId] = Subscription(
            id: subscriptionId,
            principal: principal,
            connectionId: connectionId,
            eventNames: requestedEventNames,
            subscriber: subscriber
        )
        return IPCEventSubscriptionResult(
            subscriptionId: subscriptionId,
            eventNames: requestedEventNames.sorted { $0.rawValue < $1.rawValue }
        )
    }

    public func unsubscribe(_ subscriptionId: UUID, principal: IPCPrincipal, connectionId: UUID) throws {
        guard let subscription = subscriptionsById[subscriptionId],
            subscription.principal.principalId == principal.principalId,
            subscription.connectionId == connectionId
        else {
            throw IPCEventBrokerError(reason: .subscriptionNotFound)
        }

        subscriptionsById.removeValue(forKey: subscriptionId)
    }

    package func removeSubscriptions(connectionId: UUID) {
        subscriptionsById = subscriptionsById.filter { $0.value.connectionId != connectionId }
    }

    public func publish(
        _ notification: IPCEventNotification,
        isVisible: @Sendable (IPCEventNotification, IPCPrincipal) -> Bool
    ) async -> [IPCEventDeliveryFailure] {
        var failedDeliveries: [IPCEventDeliveryFailure] = []
        let eligibleSubscriptions = subscriptionsById.values
            .filter { subscription in
                subscription.eventNames.contains(notification.name)
                    && isVisible(notification, subscription.principal)
            }

        for subscription in eligibleSubscriptions {
            let frame: String
            do {
                frame = try Self.encodeEventNotification(notification)
            } catch {
                removeSubscription(subscription.id, reason: .deliveryFailed, failures: &failedDeliveries)
                continue
            }

            do {
                switch try await subscription.subscriber.deliver(frame) {
                case .delivered:
                    break
                case .backpressure:
                    removeSubscription(subscription.id, reason: .backpressure, failures: &failedDeliveries)
                }
            } catch {
                removeSubscription(subscription.id, reason: .deliveryFailed, failures: &failedDeliveries)
            }
        }

        return failedDeliveries
    }

    public func subscriptionCount() -> Int {
        subscriptionsById.count
    }

    public static func validateInboundClientNotification(method: String) throws {
        let reservedServerEventMethods = Set(["events.notification"])
        if reservedServerEventMethods.contains(method) || IPCEventName(rawValue: method) != nil {
            throw IPCEventBrokerError(reason: .reservedInboundNotification)
        }
    }

    public static func encodeEventNotification(_ notification: IPCEventNotification) throws -> String {
        let params = try JSONRPCCodec.encodeJSONValue(notification)
        let rpcNotification = try JSONRPCNotification(method: "events.notification", params: params)
        return try JSONRPCCodec.encodeNotification(rpcNotification)
    }

    private func removeSubscription(
        _ subscriptionId: UUID,
        reason: IPCEventDeliveryFailure.Reason,
        failures: inout [IPCEventDeliveryFailure]
    ) {
        subscriptionsById.removeValue(forKey: subscriptionId)
        failures.append(IPCEventDeliveryFailure(subscriptionId: subscriptionId, reason: reason))
    }
}
