import Testing

@testable import AgentStudio

struct BridgeReviewFileClassifierTests {
    @Test("classifier identifies common review file classes")
    func classifierIdentifiesCommonReviewFileClasses() {
        #expect(classify("Sources/App/View.swift") == .source)
        #expect(classify("Tests/App/ViewTests.swift") == .test)
        #expect(classify("docs/architecture/readme.md") == .docs)
        #expect(classify("Package.swift") == .config)
        #expect(classify("Generated/API.swift") == .generated)
        #expect(classify("node_modules/pkg/index.js") == .vendor)
        #expect(classify("Fixtures/sample.json") == .fixture)
        #expect(classify("Sources/App/logo.png", isBinary: true) == .binary)
        #expect(classify("Sources/App/Large.swift", sizeBytes: 2_000_000) == .large)
    }

    private func classify(
        _ path: String,
        isBinary: Bool = false,
        sizeBytes: Int = 100
    ) -> BridgeFileClass {
        BridgeReviewFileClassifier.classify(
            path: path,
            isBinary: isBinary,
            sizeBytes: sizeBytes
        )
    }
}
