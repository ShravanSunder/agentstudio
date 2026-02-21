import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
struct CWDNormalizerTests {

    // MARK: - Nil / Empty

    @Test
    func test_normalize_nil_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize(nil)

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_normalize_emptyString_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize("")

        // Assert
        #expect(result == nil)
    }

    // MARK: - Valid Absolute Paths

    @Test
    func test_normalize_absolutePath_returnsFileURL() {
        // Act
        let result = CWDNormalizer.normalize("/Users/test/projects")

        // Assert
        #expect(result == URL(fileURLWithPath: "/Users/test/projects").standardizedFileURL)
    }

    @Test
    func test_normalize_rootPath_returnsFileURL() {
        // Act
        let result = CWDNormalizer.normalize("/")

        // Assert
        #expect(result == URL(fileURLWithPath: "/").standardizedFileURL)
    }

    @Test
    func test_normalize_trailingSlash_standardized() {
        // Act
        let result = CWDNormalizer.normalize("/tmp/foo/")

        // Assert
        // standardizedFileURL removes trailing slash for non-root paths
        #expect(result != nil)
        #expect(result?.isFileURL == true)
    }

    @Test
    func test_normalize_dotSegments_resolved() {
        // Act
        let result = CWDNormalizer.normalize("/tmp/foo/../bar")

        // Assert
        #expect(result == URL(fileURLWithPath: "/tmp/bar").standardizedFileURL)
    }

    @Test
    func test_normalize_unicodePath_returnsFileURL() {
        // Act
        let result = CWDNormalizer.normalize("/Users/test/日本語フォルダ")

        // Assert
        #expect(result != nil)
        #expect(result?.path.contains("日本語フォルダ") == true)
    }

    // MARK: - Invalid Paths

    @Test
    func test_normalize_relativePath_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize("relative/path")

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_normalize_dotRelativePath_returnsNil() {
        // Act
        let result = CWDNormalizer.normalize("./foo/bar")

        // Assert
        #expect(result == nil)
    }

    @Test
    func test_normalize_tildePrefix_returnsNil() {
        // Act — tilde is not an absolute path; shell expansion happens before OSC 7
        let result = CWDNormalizer.normalize("~/Documents")

        // Assert
        #expect(result == nil)
    }
}
