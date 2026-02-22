import Foundation
import Testing
import WebKit

@testable import AgentStudio

@MainActor
enum WebPageTestHarness {
    static func makeConfiguration() -> WebPage.Configuration {
        var config = WebPage.Configuration()
        config.websiteDataStore = .nonPersistent()
        return config
    }

    static func withManagedPage<Result>(
        _ page: WebPage,
        settleTurns: Int = 8,
        operation: (WebPage) async throws -> Result
    ) async throws -> Result {
        do {
            let result = try await operation(page)
            await teardown(page, settleTurns: settleTurns)
            return result
        } catch {
            await teardown(page, settleTurns: settleTurns)
            throw error
        }
    }

    private static func teardown(_ page: WebPage, settleTurns: Int) async {
        page.stopLoading()
        if let blankURL = URL(string: "about:blank") {
            _ = page.load(blankURL)
        }
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline, page.isLoading {
            await Task.yield()
        }
        for _ in 0..<settleTurns {
            await Task.yield()
        }
    }
}
