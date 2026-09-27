import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Dispatch
import Foundation
import SwiftUI
import Testing

@testable import AgentStudioCommandBar

@MainActor
private final class CommandBarBenchmarkPublicationRecorder {
    struct Publication {
        let sequence: SearchRequestSequence
        let publishedAtNanoseconds: UInt64
    }

    private var queuedPublications: [Publication] = []
    private var waitingContinuations: [CheckedContinuation<Publication, Never>] = []

    func record(sequence: SearchRequestSequence, generation _: SearchDocumentGeneration) {
        let publication = Publication(
            sequence: sequence,
            publishedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        if waitingContinuations.isEmpty {
            queuedPublications.append(publication)
        } else {
            waitingContinuations.removeFirst().resume(returning: publication)
        }
    }

    func next() async -> Publication {
        if !queuedPublications.isEmpty { return queuedPublications.removeFirst() }
        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }
}

@MainActor
@Suite("Command bar search 10k benchmark", .serialized)
struct CommandBarSearchBenchmarkTests {
    private let itemCount = 10_000
    private let warmSampleCount = 20

    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("10k engine diagnostic and hosted input-to-publication benchmark")
    func complete10kBenchmark() async throws {
        await engineOnlyDiagnostic()
        try await hostedControllerServiceAndView()
    }

    private func hostedControllerServiceAndView() async throws {
        let recorder = CommandBarBenchmarkPublicationRecorder()
        let loader = makeCommandBarTestOcticonLoader()
        let (traceRecorder, traceRuntime) = makeTraceRecorder()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            octiconLoader: loader,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            searchService: SearchService(performanceTraceRecorder: traceRecorder),
            performanceTraceRecorder: traceRecorder,
            recentsDefaults: CommandBarRecentsDefaultsFixture().makeDefaults()
        )
        controller.state.show(prefix: ">")
        let items = benchmarkItems()
        controller.state.pushLevel(CommandBarLevel(id: "benchmark-items", title: "Items", items: items))
        let openCaptureStarted = DispatchTime.now().uptimeNanoseconds
        controller.searchContextChanged()
        let openCaptureFinished = DispatchTime.now().uptimeNanoseconds
        await controller.pendingGenerationInstallTask?.value

        let view = CommandBarView(
            state: controller.state,
            octiconLoader: loader,
            resultSession: controller.resultSession,
            onShortcutTrigger: { _ in false },
            onExecuteItem: { _, _ in },
            onShowActions: { _ in },
            onInitialResultsPublished: {},
            onInputFocusAcknowledged: {},
            onInputChanged: { text, inputAt in
                controller.queryChanged(text: text, inputAtNanoseconds: inputAt)
            },
            onSearchContextChanged: { controller.searchContextChanged() },
            onResultPublished: { sequence, generation in
                controller.acknowledgeResultPublished(sequence: sequence, generation: generation)
                recorder.record(sequence: sequence, generation: generation)
            }
        )
        let hostingView = NSHostingView(rootView: AnyView(view.frame(width: 540, height: 420)))
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 540, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer {
            hostingView.rootView = AnyView(EmptyView())
            hostingView.layoutSubtreeIfNeeded()
            window.contentView = nil
            window.close()
        }
        hostingView.layoutSubtreeIfNeeded()

        var endToEndMilliseconds: [Double] = []
        var mainSubmitMilliseconds: [Double] = []
        var coldSequence: SearchRequestSequence?
        for sample in 0...warmSampleCount {
            let query = benchmarkQuery(sample)
            let inputAt = DispatchTime.now().uptimeNanoseconds
            controller.state.rawInput = query
            controller.queryChanged(text: query, inputAtNanoseconds: inputAt)
            let submittedAt = DispatchTime.now().uptimeNanoseconds
            let expectedSequence = SearchRequestSequence(controller.searchSequence)
            if sample == 0 { coldSequence = expectedSequence }
            await controller.pendingSearchTask?.value
            hostingView.layoutSubtreeIfNeeded()
            let publication = await recorder.next()
            #expect(publication.sequence == expectedSequence)
            #expect(controller.state.appliedSearchResult?.displayedItems.count == 1)
            endToEndMilliseconds.append(milliseconds(from: inputAt, to: publication.publishedAtNanoseconds))
            mainSubmitMilliseconds.append(milliseconds(from: inputAt, to: submittedAt))
        }

        let firstAfterOpenMilliseconds = try #require(endToEndMilliseconds.first)
        let warmEndToEndP95 = percentile95(Array(endToEndMilliseconds.dropFirst()))
        let mainSubmitP95 = percentile95(Array(mainSubmitMilliseconds.dropFirst()))
        print(
            "COMMAND_BAR_SEARCH_UI_10K "
                + "rows=\(itemCount) first_after_open_ms=\(firstAfterOpenMilliseconds) "
                + "warm_p95_ms=\(warmEndToEndP95) main_submit_p95_ms=\(mainSubmitP95)"
        )
        let changedSequence = await measureOneRowChange(
            controller: controller,
            hostingView: hostingView,
            recorder: recorder,
            items: items,
            openCaptureMilliseconds: milliseconds(from: openCaptureStarted, to: openCaptureFinished)
        )
        try await reportColdStages(
            traceRecorder: traceRecorder,
            traceRuntime: traceRuntime,
            sequence: try #require(coldSequence)
        )
        try await reportColdStages(
            traceRecorder: traceRecorder,
            traceRuntime: traceRuntime,
            sequence: changedSequence
        )
    }

    private func makeTraceRecorder() -> (AgentStudioPerformanceTraceRecorder, AgentStudioTraceRuntime) {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "command-bar-search-benchmark-\(UUIDv7.generate().uuidString)")
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "command-bar-search-benchmark",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 732,
            timeUnixNano: { 1 }
        )
        let traceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        return (traceRecorder, traceRuntime)
    }

    private func measureOneRowChange(
        controller: CommandBarPanelController,
        hostingView: NSHostingView<AnyView>,
        recorder: CommandBarBenchmarkPublicationRecorder,
        items: [CommandBarItem],
        openCaptureMilliseconds: Double
    ) async -> SearchRequestSequence {
        var changedItems = items
        controller.state.rawInput = ""
        controller.queryChanged(text: "")
        changedItems[4] = CommandBarItem(
            id: "bench-4", title: "renamed-entry", group: "Items", groupPriority: 1, action: .custom({})
        )
        controller.state.replaceLevel(CommandBarLevel(id: "benchmark-items", title: "Items", items: changedItems))
        let changeCaptureStarted = DispatchTime.now().uptimeNanoseconds
        controller.searchContextChanged()
        let changeCaptureFinished = DispatchTime.now().uptimeNanoseconds
        await controller.pendingGenerationInstallTask?.value
        let changedInputAt = DispatchTime.now().uptimeNanoseconds
        controller.state.rawInput = "renamed-entry"
        controller.queryChanged(text: "renamed-entry", inputAtNanoseconds: changedInputAt)
        let changedSequence = SearchRequestSequence(controller.searchSequence)
        await controller.pendingSearchTask?.value
        hostingView.layoutSubtreeIfNeeded()
        let changedPublication = await recorder.next()
        #expect(changedPublication.sequence == changedSequence)
        #expect(controller.state.appliedSearchResult?.displayedItems.map(\.id) == ["bench-4"])
        print(
            "COMMAND_BAR_SEARCH_UI_10K_CHANGE "
                + "first_after_one_row_change_ms=\(milliseconds(from: changedInputAt, to: changedPublication.publishedAtNanoseconds)) "
                + "open_capture_ms=\(openCaptureMilliseconds) "
                + "change_capture_ms=\(milliseconds(from: changeCaptureStarted, to: changeCaptureFinished))"
        )
        return changedSequence
    }

    private func reportColdStages(
        traceRecorder: AgentStudioPerformanceTraceRecorder,
        traceRuntime: AgentStudioTraceRuntime,
        sequence: SearchRequestSequence
    ) async throws {
        try await traceRecorder.drain()
        let outputURL = try #require(traceRuntime.outputFileURL)
        let coldStages = try searchStages(in: outputURL, sequence: sequence)
        for stage in ["submit", "queue_wait", "actor_work", "wait_for_main", "apply", "publication", "end_to_end"] {
            #expect(coldStages[stage] != nil)
        }
        print(
            "COMMAND_BAR_SEARCH_UI_10K_STAGES sequence=\(sequence.value) "
                + String(describing: coldStages)
        )
    }

    private func engineOnlyDiagnostic() async {
        let documents = (0..<itemCount).map { index in
            SearchDocument(
                itemId: SearchItemId("bench-\(index)")!,
                kind: .other,
                groupId: "Items",
                title: String(format: "entry-%05d", index),
                fields: []
            )
        }
        let documentSet = SearchDocumentSet(
            generation: SearchDocumentGeneration(1),
            groups: [SearchGroup(id: "Items", priority: 1)],
            documents: documents
        )
        let service = SearchService()
        var durations: [Double] = []
        for sample in 0...warmSampleCount {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let result = await service.search(
                SearchRequest(
                    sequence: SearchRequestSequence(UInt64(sample + 1)),
                    text: benchmarkQuery(sample),
                    recentItemIds: [],
                    documentSet: documentSet
                )
            )
            durations.append(milliseconds(from: startedAt, to: DispatchTime.now().uptimeNanoseconds))
            #expect(result.outcome == .answered)
            #expect(result.groups.first?.matches.count == 1)
        }
        print(
            "COMMAND_BAR_SEARCH_ENGINE_ONLY_10K "
                + "rows=\(itemCount) cold_ms=\(durations[0]) "
                + "warm_p95_ms=\(percentile95(Array(durations.dropFirst())))"
        )
    }

    private func benchmarkItems() -> [CommandBarItem] {
        (0..<itemCount).map { index in
            CommandBarItem(
                id: "bench-\(index)",
                title: String(format: "entry-%05d", index),
                group: "Items",
                groupPriority: 1,
                action: .custom({})
            )
        }
    }

    private func benchmarkQuery(_ sample: Int) -> String {
        String(format: "entry-%05d", sample * 479 % itemCount)
    }

    private func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end >= start ? end - start : 0) / 1_000_000
    }

    private func percentile95(_ samples: [Double]) -> Double {
        guard samples.count == warmSampleCount else { return .nan }
        var largest = -Double.infinity
        var secondLargest = -Double.infinity
        for sample in samples {
            if sample >= largest {
                secondLargest = largest
                largest = sample
            } else if sample > secondLargest {
                secondLargest = sample
            }
        }
        return secondLargest
    }

    private func searchStages(
        in outputURL: URL,
        sequence: SearchRequestSequence
    ) throws -> [String: Double] {
        let records = try String(contentsOf: outputURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
        var durations: [String: Double] = [:]
        for record in records {
            guard let attributes = record["attributes"] as? [String: Any],
                attributes["agentstudio.performance.commandbar.search.sequence"] as? Int
                    == Int(clamping: sequence.value),
                let stage = attributes["agentstudio.performance.commandbar.search.stage"] as? String,
                let elapsed = attributes["agentstudio.performance.elapsed_ms"] as? Double
            else { continue }
            durations[stage] = elapsed
        }
        return durations
    }
}
