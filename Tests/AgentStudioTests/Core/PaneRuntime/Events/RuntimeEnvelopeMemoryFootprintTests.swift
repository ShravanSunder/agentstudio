import Foundation
import Testing

@testable import AgentStudio

@Suite("RuntimeEnvelope retained payload footprint")
struct RuntimeEnvelopeMemoryFootprintTests {
    @Test("reports deterministic minimum bytes-per-envelope for common runtime payloads")
    func reportMinimumEnvelopeFootprint() async {
        let count = 20_000

        let topology = measureFootprint(label: "system.topology.worktreeRegistered", count: count) { index in
            let rootPath = URL(fileURLWithPath: "/tmp/repo-\(index)")
            return MeasuredRuntimeEnvelope(
                envelope: RuntimeEnvelope.system(
                    SystemEnvelope.test(
                        event: .topology(
                            .worktreeRegistered(
                                worktreeId: UUID(),
                                repoId: UUID(),
                                rootPath: rootPath
                            )
                        ),
                        seq: UInt64(index)
                    )
                ),
                retainedPayloadBytes: rootPath.path.utf8.count
            )
        }

        let paneBell = measureFootprint(label: "pane.terminal.bellRang", count: count) { index in
            MeasuredRuntimeEnvelope(
                envelope: RuntimeEnvelope.pane(
                    PaneEnvelope.test(
                        event: .terminal(.bellRang),
                        paneId: PaneId.generateUUIDv7(),
                        paneKind: .terminal,
                        seq: UInt64(index)
                    )
                ),
                retainedPayloadBytes: 0
            )
        }

        let filesChangedSmall = measureFootprint(
            label: "worktree.filesChanged.small(5 paths)",
            count: count
        ) { index in
            let paths = makePaths(index: index, count: 5)
            return MeasuredRuntimeEnvelope(
                envelope: RuntimeEnvelope.worktree(
                    WorktreeEnvelope.test(
                        event: .filesystem(
                            .filesChanged(
                                changeset: FileChangeset(
                                    worktreeId: UUID(),
                                    repoId: UUID(),
                                    rootPath: URL(fileURLWithPath: "/tmp/repo-\(index)"),
                                    paths: paths,
                                    timestamp: ContinuousClock().now,
                                    batchSeq: UInt64(index)
                                )
                            )
                        ),
                        repoId: UUID(),
                        worktreeId: UUID(),
                        seq: UInt64(index)
                    )
                ),
                retainedPayloadBytes: retainedPathPayloadBytes(paths)
            )
        }

        let filesChangedLarge = measureFootprint(
            label: "worktree.filesChanged.large(100 paths)",
            count: count
        ) { index in
            let paths = makePaths(index: index, count: 100)
            return MeasuredRuntimeEnvelope(
                envelope: RuntimeEnvelope.worktree(
                    WorktreeEnvelope.test(
                        event: .filesystem(
                            .filesChanged(
                                changeset: FileChangeset(
                                    worktreeId: UUID(),
                                    repoId: UUID(),
                                    rootPath: URL(fileURLWithPath: "/tmp/repo-\(index)"),
                                    paths: paths,
                                    timestamp: ContinuousClock().now,
                                    batchSeq: UInt64(index)
                                )
                            )
                        ),
                        repoId: UUID(),
                        worktreeId: UUID(),
                        seq: UInt64(index)
                    )
                ),
                retainedPayloadBytes: retainedPathPayloadBytes(paths)
            )
        }

        print("[RuntimeEnvelopeMemory] count=\(count)")
        for sample in [topology, paneBell, filesChangedSmall, filesChangedLarge] {
            print(
                "[RuntimeEnvelopeMemory] \(sample.label): retainedPayload=\(sample.retainedPayloadBytes) bytes, minimumPerEnvelope=\(sample.minimumBytesPerEnvelope) bytes"
            )
        }

        #expect(topology.minimumBytesPerEnvelope > paneBell.minimumBytesPerEnvelope)
        #expect(filesChangedSmall.minimumBytesPerEnvelope > topology.minimumBytesPerEnvelope)
        #expect(filesChangedLarge.minimumBytesPerEnvelope > filesChangedSmall.minimumBytesPerEnvelope)
    }
}

private struct MeasuredRuntimeEnvelope {
    let envelope: RuntimeEnvelope
    let retainedPayloadBytes: Int
}

private struct FootprintSample {
    let label: String
    let retainedPayloadBytes: Int
    let minimumBytesPerEnvelope: Int
}

private func measureFootprint(
    label: String,
    count: Int,
    makeEnvelope: (Int) -> MeasuredRuntimeEnvelope
) -> FootprintSample {
    var storage: [RuntimeEnvelope] = []
    storage.reserveCapacity(count)
    var retainedPayloadBytes = 0

    for index in 0..<count {
        let measuredEnvelope = makeEnvelope(index)
        storage.append(measuredEnvelope.envelope)
        retainedPayloadBytes += measuredEnvelope.retainedPayloadBytes
    }

    withExtendedLifetime(storage) {}

    return FootprintSample(
        label: label,
        retainedPayloadBytes: retainedPayloadBytes,
        minimumBytesPerEnvelope: MemoryLayout<RuntimeEnvelope>.stride + retainedPayloadBytes / count
    )
}

private func makePaths(index: Int, count: Int) -> [String] {
    (0..<count).map { pathIndex in
        "src/feature\(index % 100)/module\(pathIndex)/file\(index)-\(pathIndex).swift"
    }
}

private func retainedPathPayloadBytes(_ paths: [String]) -> Int {
    paths.count * MemoryLayout<String>.stride + paths.reduce(0) { $0 + $1.utf8.count }
}
