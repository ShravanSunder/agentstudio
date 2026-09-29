import Foundation
import Synchronization

/// One durable pending/settled pair per fact expectation, in the lane's held-step log.
package struct ExpectationLog: Sendable {
    private static let nextID = Atomic<UInt64>(0)

    package static let environment = Self(
        path: ProcessInfo.processInfo.environment[HeldStepEventLog.environmentVariableName]
            .flatMap { $0.isEmpty ? nil : $0 }
    )

    package let path: String?

    package init(path: String?) {
        self.path = path
    }

    @discardableResult
    package func expecting(expectedCase: String, scope: String, test: String, callSite: String) -> String {
        let uniqueID = Self.nextID.wrappingAdd(1, ordering: .relaxed).newValue
        let identifier = "\(getpid())-\(uniqueID)"
        TestEventLogWriter.append(
            "expecting\t\(identifier)\t\(Self.field(expectedCase))\t\(Self.field(scope))\t\(Self.field(test))\t\(Self.field(callSite))\n",
            path: path
        )
        return identifier
    }

    package func settled(_ identifier: String, outcome: Settlement) {
        TestEventLogWriter.append("settled\t\(identifier)\t\(outcome.rawValue)\n", path: path)
    }

    package enum Settlement: String, Sendable {
        case matched
        case unexpected
        case ended
        case cancelled
        case lost
    }

    private static func field(_ text: String) -> String {
        String(text.prefix(200))
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
