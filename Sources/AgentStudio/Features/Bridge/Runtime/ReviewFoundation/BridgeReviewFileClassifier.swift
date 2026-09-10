import Foundation

enum BridgeReviewFileClassifier {
    private static let largeFileThresholdBytes = 1_000_000

    static func classify(path: String, isBinary: Bool, sizeBytes: Int) -> BridgeFileClass {
        if isBinary {
            return .binary
        }
        if sizeBytes >= largeFileThresholdBytes {
            return .large
        }

        let normalizedPath = path.lowercased()
        let pathComponents = normalizedPath.split(separator: "/").map(String.init)

        if pathComponents.contains("node_modules")
            || pathComponents.contains("vendor")
            || pathComponents.contains(".build")
            || pathComponents.contains("deriveddata")
        {
            return .vendor
        }
        if pathComponents.contains("generated")
            || normalizedPath.contains("/generated/")
            || normalizedPath.hasSuffix(".generated.swift")
        {
            return .generated
        }
        if pathComponents.contains("fixtures")
            || pathComponents.contains("__fixtures__")
            || pathComponents.contains("test-fixtures")
            || pathComponents.contains("testdata")
            || normalizedPath.contains("/fixtures/")
        {
            return .fixture
        }
        if pathComponents.contains("tests")
            || pathComponents.contains("test")
            || pathComponents.contains("__tests__")
            || normalizedPath.hasSuffix("tests.swift")
            || isScriptTestPath(normalizedPath)
        {
            return .test
        }
        if pathComponents.contains("docs")
            || normalizedPath.hasPrefix("docs/")
            || normalizedPath.hasSuffix(".md")
            || normalizedPath.hasSuffix(".mdx")
            || isDocumentationFilename(normalizedPath)
        {
            return .docs
        }
        if isConfigPath(normalizedPath) {
            return .config
        }
        if isSourcePath(normalizedPath) {
            return .source
        }
        return .unknown
    }

    private static func isConfigPath(_ path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent
        return filename == "package.swift"
            || filename == "package.json"
            || filename == "tsconfig.json"
            || filename == "vite.config.ts"
            || filename == "vitest.config.ts"
            || filename == "astro.config.ts"
            || filename == "postcss.config.mjs"
            || filename == ".mise.toml"
            || filename.hasSuffix(".yml")
            || filename.hasSuffix(".yaml")
            || filename.hasSuffix(".toml")
            || filename.hasSuffix(".json")
    }

    private static func isDocumentationFilename(_ path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent
        return ["readme", "license", "licence", "changelog", "contributing"].contains(filename)
    }

    private static func isScriptTestPath(_ path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent as NSString
        let scriptExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mts", "cts", "mjs", "cjs"]
        guard scriptExtensions.contains(filename.pathExtension) else { return false }
        let stem = filename.deletingPathExtension
        return stem.hasSuffix(".test") || stem.hasSuffix(".spec")
    }

    private static func isSourcePath(_ path: String) -> Bool {
        path.hasSuffix(".swift")
            || path.hasSuffix(".ts")
            || path.hasSuffix(".tsx")
            || path.hasSuffix(".js")
            || path.hasSuffix(".jsx")
            || path.hasSuffix(".css")
    }
}
