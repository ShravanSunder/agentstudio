import Foundation
import Testing
import WebKit

@testable import AgentStudioBridge

/// Event-driven waits for the WebKit lane.
///
/// Every one of these replaces a `ContinuousClock` deadline poll. None takes a
/// timeout: the lane's inactivity watchdog is the hang bound, and a deadline here
/// is actively wrong — a hidden headless page schedules no animation frames, so
/// DOM state behind a rAF commit has no sound upper bound and any N you pick is a
/// verdict about machine speed rather than about the product.
enum WebPageEventWaits {
    /// Suspends until the page stops loading.
    ///
    /// `WebPage` is `@Observable`, so this parks on the page's own change
    /// notification instead of sampling. The loop re-registers because
    /// `onChange` fires on willSet and is one-shot; it suspends every pass rather
    /// than spinning.
    @MainActor
    static func waitForNavigationToFinish(_ page: WebPage) async {
        await waitForPageChange(on: page) { !page.isLoading }
    }

    /// Suspends until the page reports the expected title.
    @MainActor
    static func waitForTitle(_ page: WebPage, equals expectedTitle: String) async {
        await waitForPageChange(on: page) { page.title == expectedTitle }
    }

    /// Suspends until a JavaScript reader returns a value, and answers with it.
    ///
    /// `readerBody` is a JavaScript function body that returns the value once its
    /// condition holds and `null` (or `undefined`) while it does not. It runs once
    /// up front and then again from `MutationObserver`s on
    /// `document.documentElement` and every open shadow root, watching `childList`,
    /// `subtree`, `attributes` and `characterData` — every channel through which
    /// the Bridge app publishes test-visible state. Observer callbacks are
    /// microtasks fired by the mutation itself: they are NOT throttled by page
    /// visibility or requestAnimationFrame, which is what makes this sound on the
    /// hidden headless page the lane runs, where no animation frames are scheduled
    /// at all.
    ///
    /// It answers with whatever the reader sees at the moment a mutation is
    /// delivered, so a value that appears and is replaced inside one mutation batch
    /// can be missed. Every caller here waits for a settled end state, not a
    /// transient. A throw from the first evaluation propagates; a throw from a later
    /// one would be swallowed by the observer, so readers must be null-safe.
    @MainActor
    static func waitForDocumentValue(
        _ page: WebPage,
        reader readerBody: String,
        arguments: [String: Any] = [:]
    ) async throws -> Any? {
        try await page.callJavaScript(
            """
            const readDocumentValue = () => { \(readerBody) };
            return await new Promise((resolve) => {
              const observers = [];
              const observedRoots = new WeakSet();
              const disconnectObservers = () => {
                for (const observer of observers) observer.disconnect();
              };
              const attempt = () => {
                const value = readDocumentValue();
                if (value === null || value === undefined) { return false; }
                resolve(value);
                disconnectObservers();
                return true;
              };
              if (attempt()) { return; }
              const observeMutations = (root) => {
                if (observedRoots.has(root)) return;
                observedRoots.add(root);
                const observer = new MutationObserver(() => {
                  observeNestedOpenShadowRoots(root);
                  attempt();
                });
                observer.observe(root, {
                  attributes: true,
                  characterData: true,
                  childList: true,
                  subtree: true
                });
                observers.push(observer);
                observeNestedOpenShadowRoots(root);
              };
              const observeNestedOpenShadowRoots = (root) => {
                for (const element of root.querySelectorAll('*')) {
                  if (element.shadowRoot !== null) {
                    observeMutations(element.shadowRoot);
                  }
                }
              };
              observeMutations(document.documentElement);
              attempt();
            });
            """,
            arguments: arguments
        )
    }

    /// Suspends until WebKit announces the requested document visibility state.
    @MainActor
    static func waitForDocumentVisibility(
        _ page: WebPage,
        equals expectedVisibility: String
    ) async throws -> String {
        let value = try await page.callJavaScript(
            """
            const expectedVisibility = expected;
            return await new Promise((resolve) => {
              const handleVisibilityChange = () => {
                if (document.visibilityState !== expectedVisibility) { return; }
                document.removeEventListener('visibilitychange', handleVisibilityChange);
                resolve(document.visibilityState);
              };
              if (document.visibilityState === expectedVisibility) {
                resolve(document.visibilityState);
                return;
              }
              document.addEventListener('visibilitychange', handleVisibilityChange);
            });
            """,
            arguments: ["expected": expectedVisibility]
        )
        guard let value = value as? String else {
            throw WebPageEventWaitError.documentVisibilityUnavailable
        }
        return value
    }

    /// Suspends until `document.querySelector(selector)` is non-null.
    @MainActor
    static func waitForDocumentSelector(_ page: WebPage, _ selector: String) async throws {
        _ = try await waitForDocumentValue(
            page,
            reader: "return document.querySelector(selector) === null ? null : true;",
            arguments: ["selector": selector]
        )
    }

    /// Suspends until the controller's bridge handshake has completed.
    ///
    /// `isBridgeReady` is a stored property of an `@Observable` type, so the
    /// transition is observable and needs no production seam.
    @MainActor
    static func waitForBridgeReady(_ controller: BridgePaneController) async {
        while !controller.isBridgeReady {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = controller.isBridgeReady
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    /// Parks on the page's own observation until `condition` holds.
    @MainActor
    private static func waitForPageChange(
        on page: WebPage,
        until condition: @escaping () -> Bool
    ) async {
        while !condition() {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = page.isLoading
                    _ = page.title
                    _ = page.url
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}

private enum WebPageEventWaitError: Error {
    case documentVisibilityUnavailable
}

/// The element `hasReviewShell` is computed from
/// (`BridgePaneController+IPCProjection.swift:449`). The wait and the assertion
/// must read the same element or the wait proves nothing about the assertion.
let bridgeReviewShellSelector = "[data-testid=\"review-viewer-shell\"]"
