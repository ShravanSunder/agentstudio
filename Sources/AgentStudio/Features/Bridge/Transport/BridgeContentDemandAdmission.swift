import Foundation

enum BridgeContentDemandInterest: String, Equatable, Sendable {
    case selected
    case visible
    case nearby
    case speculative
    case background
    case unspecified

    static let queryKey = "interest"

    static func parse(_ resourceURL: String) -> Self? {
        guard let components = URLComponents(string: resourceURL) else {
            return nil
        }
        let values = (components.queryItems ?? [])
            .filter { $0.name == queryKey }
            .map(\.value)
        guard values.count <= 1 else {
            return nil
        }
        guard let value = values.first else {
            return .unspecified
        }
        return value.flatMap(Self.init(rawValue:))
    }

    static func parseQueryValue(_ value: String?) -> Self? {
        guard let value else {
            return nil
        }
        return Self(rawValue: value)
    }

    var isUserBlocking: Bool {
        self == .selected || self == .visible
    }

    var isBackgroundFill: Bool {
        self == .background
    }
}

actor BridgeContentDemandAdmission {
    private var pendingUserDemandCount = 0
    private var backgroundWaiters: [CheckedContinuation<Void, Never>] = []

    func start(_ interest: BridgeContentDemandInterest) async {
        if interest.isUserBlocking {
            pendingUserDemandCount += 1
            return
        }
        if interest.isBackgroundFill {
            await waitForBackgroundTurn()
        }
    }

    func finish(_ interest: BridgeContentDemandInterest) {
        guard interest.isUserBlocking, pendingUserDemandCount > 0 else {
            return
        }
        pendingUserDemandCount -= 1
        if pendingUserDemandCount == 0 {
            resumeBackgroundWaiters()
        }
    }

    func waitForBackgroundTurn(_ interest: BridgeContentDemandInterest) async {
        guard interest.isBackgroundFill else {
            return
        }
        await waitForBackgroundTurn()
    }

    func waitForBackgroundTurn() async {
        guard pendingUserDemandCount >= AppPolicies.Bridge.contentBackgroundFillUserInterestYieldThreshold else {
            return
        }
        await withCheckedContinuation { continuation in
            backgroundWaiters.append(continuation)
        }
    }

    private func resumeBackgroundWaiters() {
        let waiters = backgroundWaiters
        backgroundWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
