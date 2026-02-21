import XCTest

@testable import AgentStudio

final class CWDNormalizerTests: XCTestCase {

    // MARK: - Nil / Empty

    func test_normalize_nil_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize(nil)

        // Assert
        XCTAssertNil(result)
    }

    func test_normalize_emptyString_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize("")

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - Valid Absolute Paths

    func test_normalize_absolutePath_returnsFileURL() {
        // Act
        let result = CWDNormalizer.normalize("/Users/test/projects")

        // Assert
        XCTAssertEqual(result, URL(fileURLWithPath: "/Users/test/projects").standardizedFileURL)
    }

    func test_normalize_rootPath_returnsFileURL() {
        // Act
        let result = CWDNormalizer.normalize("/")

        // Assert
        XCTAssertEqual(result, URL(fileURLWithPath: "/").standardizedFileURL)
    }

    func test_normalize_trailingSlash_standardized() {
        // Act
        let result = CWDNormalizer.normalize("/tmp/foo/")

        // Assert
        // standardizedFileURL removes trailing slash for non-root paths
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isFileURL)
    }

    func test_normalize_dotSegments_resolved() {
        // Act
        let result = CWDNormalizer.normalize("/tmp/foo/../bar")

        // Assert
        XCTAssertEqual(result, URL(fileURLWithPath: "/tmp/bar").standardizedFileURL)
    }

    func test_normalize_unicodePath_returnsFileURL() {
        // Act
        let result = CWDNormalizer.normalize("/Users/test/日本語フォルダ")

        // Assert
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.path.contains("日本語フォルダ"))
    }

    // MARK: - Invalid Paths

    func test_normalize_relativePath_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize("relative/path")

        // Assert
        XCTAssertNil(result)
    }

    func test_normalize_dotRelativePath_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize("./foo/bar")

        // Assert
        XCTAssertNil(result)
    }

    func test_normalize_tildePrefix_returnsNil() {
        // Act — tilde is not an absolute path; shell expansion happens before OSC 7
        let result = CWDNormalizer.normalize("~/Documents")

        // Assert
        XCTAssertNil(result)
    }
}
