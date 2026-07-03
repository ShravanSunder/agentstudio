import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct GlobalPreferencesBootstrapPerformanceTests {
    private static let sampleCount = 1000
    private static let p95BudgetMilliseconds = 2.0
    private static let slowSampleThresholdMilliseconds = 10.0
    private static let allowedSlowSampleCount = 10

    @Test("global preferences loader stays within startup budget")
    func globalPreferencesLoaderStaysWithinStartupBudget() throws {
        let cases = try [
            LoaderCase(name: "missing", rootURL: makeTemporaryRoot()),
            LoaderCase(
                name: "valid",
                rootURL: makeTemporaryRoot(
                    json: """
                        {
                          "schemaVersion": 1,
                          "observability": {
                            "enabled": true,
                            "traceTags": "*",
                            "traceBackend": "otlp",
                            "traceFlush": "buffered",
                            "otlpEndpoint": "http://127.0.0.1:4318"
                          }
                        }
                        """)),
        ]

        for loaderCase in cases {
            for _ in 0..<25 {
                _ = GlobalPreferencesBootstrap.load(
                    environment: ["AGENTSTUDIO_DATA_DIR": loaderCase.rootURL.path],
                    releaseChannel: .stable,
                    isDebugBuild: false
                )
            }

            var samples: [Double] = []
            samples.reserveCapacity(Self.sampleCount)
            for _ in 0..<Self.sampleCount {
                let result = GlobalPreferencesBootstrap.load(
                    environment: ["AGENTSTUDIO_DATA_DIR": loaderCase.rootURL.path],
                    releaseChannel: .stable,
                    isDebugBuild: false
                )
                samples.append(result.elapsedMilliseconds)
            }

            let sortedSamples = samples.sorted()
            let p95Index = Int((Double(sortedSamples.count) * 0.95).rounded(.up)) - 1
            let p95 = sortedSamples[max(0, min(p95Index, sortedSamples.count - 1))]
            let maximum = sortedSamples.last ?? 0
            let slowSampleCount = sortedSamples.count { $0 > Self.slowSampleThresholdMilliseconds }
            print(
                "global-preferences-loader \(loaderCase.name) count=\(samples.count) "
                    + "p95_ms=\(p95) max_ms=\(maximum) "
                    + "slow_samples_over_\(Self.slowSampleThresholdMilliseconds)ms=\(slowSampleCount)"
            )

            #expect(
                p95 <= Self.p95BudgetMilliseconds,
                "\(loaderCase.name) p95 \(p95) ms exceeded \(Self.p95BudgetMilliseconds) ms"
            )
            #expect(
                slowSampleCount <= Self.allowedSlowSampleCount,
                "\(loaderCase.name) \(slowSampleCount) samples exceeded \(Self.slowSampleThresholdMilliseconds) ms"
            )
        }
    }

    private struct LoaderCase {
        let name: String
        let rootURL: URL
    }

    private func makeTemporaryRoot(json: String? = nil) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "agentstudio-global-preferences-performance-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if let json {
            try json.write(
                to: AppDataPaths.globalPreferencesURL(
                    environment: ["AGENTSTUDIO_DATA_DIR": rootURL.path],
                    releaseChannel: .stable,
                    isDebugBuild: false
                ),
                atomically: true,
                encoding: .utf8
            )
        }
        return rootURL
    }
}
