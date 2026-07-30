import Foundation
import Testing

@testable import AgentStudioInfrastructure

@MainActor
struct DerivedValueMemoizationTests {
    @Test
    func cacheHitAvoidsRecomputeWhenInputRevisionsAreUnchanged() {
        let sourceRevision = AtomRevision()
        var sourceValue = 2
        var computeCount = 0
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: {
                computeCount += 1
                return sourceValue * 2
            }
        )

        #expect(derived.value == 4)
        sourceValue = 3
        #expect(derived.value == 4)
        #expect(computeCount == 1)
    }

    @Test
    func recomputeWithEqualOutputDoesNotBumpOwnRevision() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        var computeCount = 0
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: {
                computeCount += 1
                return sourceValue % 2
            }
        )

        #expect(derived.value == 1)
        let revisionAfterFirstRead = derived.revision.value

        sourceValue = 3
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(derived.value == 1)
        #expect(computeCount == 2)
        #expect(derived.revision.value == revisionAfterFirstRead)
    }

    @Test
    func recomputeWithChangedOutputBumpsOwnRevisionOnce() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue }
        )

        #expect(derived.value == 1)
        let revisionAfterFirstRead = derived.revision.value

        sourceValue = 2
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(derived.value == 2)
        #expect(derived.revision.value == revisionAfterFirstRead + 1)
    }

    @Test
    func chainedDerivedReadsUpstreamValueBeforeUpstreamRevision() {
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let upstream = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue * 2 }
        )
        var latestUpstreamValue = 0
        let downstream = DerivedValue<Int>(
            inputRevisions: {
                latestUpstreamValue = upstream.value
                return [upstream.revision.value]
            },
            isContentEqual: ==,
            compute: { latestUpstreamValue + 1 }
        )

        #expect(downstream.value == 3)

        sourceValue = 2
        let sourceMutation = AtomMutationContext(aggregateRevision: sourceRevision)
        sourceMutation.recordAcceptedChange()
        sourceMutation.commit()

        #expect(downstream.value == 5)
        #expect(upstream.revision.value == 1)
        #expect(downstream.revision.value == 1)
    }

    @Test
    func derivedValueEmitsComputeDurationAndCacheReuseTelemetry() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("derived-value-telemetry-\(UUID().uuidString)", isDirectory: true)
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "derived-value-telemetry",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 918,
            timeUnixNano: { 778 }
        )
        AtomPerformanceTelemetry.shared.configure(traceRuntime: runtime)
        defer { AtomPerformanceTelemetry.shared.resetForTests() }
        let sourceRevision = AtomRevision()
        var sourceValue = 1
        let derived = DerivedValue<Int>(
            inputRevisions: { [sourceRevision.value] },
            isContentEqual: ==,
            compute: { sourceValue }
        )

        #expect(derived.value == 1)
        #expect(derived.value == 1)
        sourceValue = 2
        sourceRevision.bump()
        #expect(derived.value == 2)
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n").map(String.init)
        let derivedLines = lines.filter {
            $0.contains("\"body\":\"performance.atom.derived\"")
        }
        let computeLines = derivedLines.filter {
            $0.contains("\"agentstudio.performance.atom.operation\":\"compute\"")
        }
        let cacheHitLines = derivedLines.filter {
            $0.contains("\"agentstudio.performance.atom.operation\":\"cache_hit\"")
        }

        #expect(computeLines.count == 2)
        #expect(cacheHitLines.count == 1)
        #expect(
            computeLines.allSatisfy {
                $0.contains("\"agentstudio.performance.elapsed_ms\":")
            })
        #expect(
            cacheHitLines.allSatisfy {
                !$0.contains("\"agentstudio.performance.elapsed_ms\":")
            })
    }
}
