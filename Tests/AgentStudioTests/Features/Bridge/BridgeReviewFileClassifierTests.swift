import Testing

@testable import AgentStudioBridge

struct BridgeReviewFileClassifierTests {
    @Test(
        "recognized tool configuration stays out of Source",
        arguments: ["BridgeWeb/vitest.config.ts", "web/astro.config.ts", "BridgeWeb/postcss.config.mjs"])
    func recognizesToolConfiguration(path: String) {
        #expect(classify(path) == .config)
    }

    @Test(
        "extensionless project documentation uses Documentation",
        arguments: ["LICENSE", "README", "CHANGELOG", "CONTRIBUTING", "docs/LICENSE"])
    func recognizesDocumentationNames(path: String) {
        #expect(classify(path) == .docs)
    }

    @Test("testdata is fixture data rather than JSON configuration")
    func recognizesTestDataDirectory() {
        #expect(classify("testdata/golden.json") == .fixture)
        #expect(classify("testdata-extra/golden.json") == .config)
    }

    @Test(
        "JavaScript and TypeScript test suffixes are Tests",
        arguments: ["ts", "tsx", "js", "jsx", "mts", "cts", "mjs", "cjs"])
    func recognizesScriptTestSuffixes(fileExtension: String) {
        for marker in ["test", "spec"] {
            #expect(classify("src/component.\(marker).\(fileExtension)") == .test)
        }
    }

    @Test(
        "test and fixture directories match complete path components",
        arguments: [
            ("src/__tests__/component.tsx", BridgeFileClass.test),
            ("src/test-fixtures/component.tsx", .fixture),
            ("src/TEST-FIXTURES/sample.json", .fixture),
            ("tests/test-fixtures/component.test.tsx", .fixture),
            ("src/latest/component.tsx", .source),
            ("src/test-fixtures-extra/component.tsx", .source),
            ("src/component.test.tsx.backup", .unknown),
        ])
    func recognizesDirectoryBoundaries(path: String, expected: BridgeFileClass) {
        #expect(classify(path) == expected)
    }

    @Test("test naming does not override binary large vendor or generated classification")
    func preservesClassificationPrecedence() {
        let path = "vendor/generated/test-fixtures/component.test.tsx"
        #expect(classify(path, isBinary: true, sizeBytes: 2_000_000) == .binary)
        #expect(classify(path, sizeBytes: 1_000_000) == .large)
        #expect(classify(path) == .vendor)
        #expect(classify("generated/test-fixtures/component.test.tsx") == .generated)
        #expect(classify("docs/component.spec.jsx") == .test)
    }

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
        #expect(classify("assets/logo.png") == .unknown)
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
