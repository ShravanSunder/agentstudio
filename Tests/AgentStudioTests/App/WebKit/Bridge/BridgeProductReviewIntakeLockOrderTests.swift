import Foundation
import Testing

@testable import AgentStudioTestSupport

extension WebKitSerializedTests {
    @Suite("Bridge product Review intake lock order", .serialized)
    struct BridgeProductReviewIntakeLockOrderTests {
        @Test("Review intake closes product admission before foreground scheduling")
        func reviewIntakeClosesProductAdmissionBeforeForegroundScheduling() throws {
            // Arrange
            let projectRoot = TestPathResolver.projectRoot(from: #filePath)
            let sourceURL = URL(fileURLWithPath: projectRoot)
                .appending(
                    path:
                        "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift"
                )
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let handlerStart = try #require(
                source.range(of: "func handleCommittedProductReviewIntakeReady(")
            )
            let handlerEnd = try #require(
                source.range(
                    of: "\n}\n\n@MainActor\nextension BridgePaneController {",
                    range: handlerStart.lowerBound..<source.endIndex
                )
            )
            let handler = String(source[handlerStart.lowerBound..<handlerEnd.lowerBound])
            let productAdmissionStarts = ranges(
                of: "productAdmission.withValidAdmission(",
                in: handler
            )
            let productAdmissionEnds = [
                try #require(handler.range(of: "}) == true")),
                try #require(handler.range(of: "}) != nil")),
            ]
            let schedulingCalls = ranges(
                of: "scheduleInitialReviewPackageLoadIfPossible(",
                in: handler
            )

            // Act / Assert
            #expect(productAdmissionStarts.count == 2)
            #expect(productAdmissionEnds.count == 2)
            #expect(schedulingCalls.count == 2)
            #expect(productAdmissionEnds[0].upperBound <= schedulingCalls[0].lowerBound)
            #expect(productAdmissionEnds[1].upperBound <= schedulingCalls[1].lowerBound)
        }
    }
}

private func ranges(of needle: String, in source: String) -> [Range<String.Index>] {
    var matches: [Range<String.Index>] = []
    var remainingRange = source.startIndex..<source.endIndex
    while let match = source.range(of: needle, range: remainingRange) {
        matches.append(match)
        remainingRange = match.upperBound..<source.endIndex
    }
    return matches
}
