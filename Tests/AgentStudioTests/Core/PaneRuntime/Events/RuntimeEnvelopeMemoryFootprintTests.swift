import Darwin.Mach
import Foundation
import Testing

@testable import AgentStudio

@Suite("RuntimeEnvelope memory footprint")
struct RuntimeEnvelopeMemoryFootprintTests {
    @Test("reports approximate bytes-per-envelope for common runtime payloads")
    func reportApproximateEnvelopeFootprint() async {
        let count = 20_000

        let topology = measureFootprint(label: "system.topology.worktreeRegistered", count: count) { index in
            RuntimeEnvelope.system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: UUID(),
                            repoId: UUID(),
                            rootPath: URL(fileURLWithPath: "/tmp/repo-\(index)")
                        )
                    ),
                    seq: UInt64(index)
                )
            )
        }

        let paneBell = measureFootprint(label: "pane.terminal.bellRang", count: count) { index in
            RuntimeEnvelope.pane(
                PaneEnvelope.test(
                    event: .terminal(.bellRang),
                    paneId: PaneId(),
                    paneKind: .terminal,
                    seq: UInt64(index)
                )
            )
        }

        let filesChangedSmall = measureFootprint(label: "worktree.filesChanged.small(5 paths)", count: count) {
            index in
            RuntimeEnvelope.worktree(
                WorktreeEnvelope.test(
                    event: .filesystem(
                        .filesChanged(
                            changeset: FileChangeset(
                                worktreeId: UUID(),
                                repoId: UUID(),
                                rootPath: URL(fileURLWithPath: "/tmp/repo-\(index)"),
                                paths: makePaths(index: index, count: 5),
                                timestamp: ContinuousClock().now,
                                batchSeq: UInt64(index)
                            )
                        )
                    ),
                    repoId: UUID(),
                    worktreeId: UUID(),
                    seq: UInt64(index)
                )
            )
        }

        let filesChangedLarge = measureFootprint(label: "worktree.filesChanged.large(100 paths)", count: count) {
            index in
            RuntimeEnvelope.worktree(
                WorktreeEnvelope.test(
                    event: .filesystem(
                        .filesChanged(
                            changeset: FileChangeset(
                                worktreeId: UUID(),
                                repoId: UUID(),
                                rootPath: URL(fileURLWithPath: "/tmp/repo-\(index)"),
                                paths: makePaths(index: index, count: 100),
                                timestamp: ContinuousClock().now,
                                batchSeq: UInt64(index)
                            )
                        )
                    ),
                    repoId: UUID(),
                    worktreeId: UUID(),
                    seq: UInt64(index)
                )
            )
        }

        print("[RuntimeEnvelopeMemory] count=\(count)")
        for sample in [topology, paneBell, filesChangedSmall, filesChangedLarge] {
            print(
                "[RuntimeEnvelopeMemory] \(sample.label): totalDelta=\(sample.totalDeltaBytes) bytes, approxPerEnvelope=\(sample.approxBytesPerEnvelope) bytes"
            )
        }

        #expect(topology.approxBytesPerEnvelope > 0)
        #expect(paneBell.approxBytesPerEnvelope > 0)
        #expect(filesChangedSmall.approxBytesPerEnvelope > 0)
        #expect(filesChangedLarge.approxBytesPerEnvelope > filesChangedSmall.approxBytesPerEnvelope)
    }
}

private struct FootprintSample {
    let label: String
    let totalDeltaBytes: UInt64
    let approxBytesPerEnvelope: UInt64
}

private func measureFootprint(
    label: String,
    count: Int,
    makeEnvelope: (Int) -> RuntimeEnvelope
) -> FootprintSample {
    var storage: [RuntimeEnvelope] = []
    storage.reserveCapacity(count)

    _ = currentResidentMemoryBytes()
    let before = currentResidentMemoryBytes()
    for index in 0..<count {
        storage.append(makeEnvelope(index))
    }
    let after = currentResidentMemoryBytes()

    let delta = after > before ? after - before : 0
    let approxPerEnvelope = count > 0 ? UInt64(Double(delta) / Double(count)) : 0

    withExtendedLifetime(storage) {}

    return FootprintSample(
        label: label,
        totalDeltaBytes: delta,
        approxBytesPerEnvelope: approxPerEnvelope
    )
}

private func currentResidentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let kernResult = withUnsafeMutablePointer(to: &info) { infoPointer in
        infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                reboundPointer,
                &count
            )
        }
    }

    guard kernResult == KERN_SUCCESS else {
        return 0
    }

    return UInt64(info.resident_size)
}

private func makePaths(index: Int, count: Int) -> [String] {
    (0..<count).map { pathIndex in
        "src/feature\(index % 100)/module\(pathIndex)/file\(index)-\(pathIndex).swift"
    }
}
