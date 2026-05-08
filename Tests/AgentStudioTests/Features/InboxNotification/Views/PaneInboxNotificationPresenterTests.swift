import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneInboxNotificationPresenter")
struct PaneInboxNotificationPresenterTests {
    private func makeTraceRuntime(name: String, processIdentifier: Int32) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": name,
                "AGENTSTUDIO_TRACE_TAGS": "paneInbox",
            ]),
            processIdentifier: processIdentifier,
            sessionID: "pane-inbox-presenter-session",
            timeUnixNano: { 2222 }
        )
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-pane-inbox-presenter-trace-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("open request stores pane ids")
    func openRequestStoresPaneIds() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let paneIds = [UUID(), UUID()]

        presenter.open(parentPaneId: parentPaneId, paneIds: paneIds)

        #expect(presenter.request?.parentPaneId == parentPaneId)
        #expect(presenter.request?.paneIds == paneIds)
        #expect(presenter.request?.intent == .open)
    }

    @Test("toggle closes the same pane inbox target")
    func toggleSamePendingTargetClearsRequest() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let childPaneId = UUID()

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request?.parentPaneId == parentPaneId)

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request == nil)
    }

    @Test("toggle treats pane inbox target identity as order independent")
    func toggleTreatsPaneInboxTargetIdentityAsOrderIndependent() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let childPaneId = UUID()

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
        #expect(presenter.request?.intent == .open)

        presenter.toggle(parentPaneId: parentPaneId, paneIds: [childPaneId, parentPaneId])
        #expect(presenter.request == nil)
    }

    @Test("toggle sends close request for an already presented target")
    func togglePresentedTargetSendsCloseRequest() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let childPaneId = UUID()
        let paneIds = [parentPaneId, childPaneId]

        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: true)
        presenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)

        #expect(presenter.request?.parentPaneId == parentPaneId)
        #expect(presenter.request?.paneIds == paneIds)
        #expect(presenter.request?.intent == .close)
    }

    @Test("dismissed target can be opened again")
    func dismissedTargetCanBeOpenedAgain() {
        let presenter = PaneInboxNotificationPresenter()
        let parentPaneId = UUID()
        let paneIds = [parentPaneId]

        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: true)
        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: false)
        presenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)

        #expect(presenter.request?.intent == .open)
    }

    @Test("toggle replaces a different pane inbox target")
    func toggleDifferentTargetReplaces() {
        let presenter = PaneInboxNotificationPresenter()
        let firstParentPaneId = UUID()
        let secondParentPaneId = UUID()

        presenter.toggle(parentPaneId: firstParentPaneId, paneIds: [firstParentPaneId])
        presenter.toggle(parentPaneId: secondParentPaneId, paneIds: [secondParentPaneId])

        #expect(presenter.request?.parentPaneId == secondParentPaneId)
        #expect(presenter.request?.paneIds == [secondParentPaneId])
    }

    @Test("pane inbox presenter traces low-volume request and presentation state changes")
    func paneInboxPresenterTracesLowVolumeRequestAndPresentationStateChanges() async throws {
        let traceRuntime = makeTraceRuntime(name: "pane-inbox-presenter", processIdentifier: 263)
        let presenter = PaneInboxNotificationPresenter(traceRuntime: traceRuntime)
        let parentPaneId = UUID()
        let childPaneId = UUID()
        let paneIds = [parentPaneId, childPaneId]

        presenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)
        presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: true)

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("pane inbox presenter should write request and presentation traces") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"paneInbox.presentationChanged\"") == true
        }

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"paneInbox.requested\""))
        #expect(contents.contains("\"agentstudio.pane_inbox.intent\":\"open\""))
        #expect(contents.contains("\"agentstudio.pane_inbox.presented\":true"))
        #expect(contents.contains("\"agentstudio.pane.parent_id\":\"\(parentPaneId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.pane.scope_count\":2"))
    }

    @Test("pane inbox presenter traces row activation target")
    func paneInboxPresenterTracesRowActivationTarget() async throws {
        let traceRuntime = makeTraceRuntime(name: "pane-inbox-row-activation", processIdentifier: 264)
        let presenter = PaneInboxNotificationPresenter(traceRuntime: traceRuntime)
        let parentPaneId = UUID()
        let childPaneId = UUID()
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Done",
            body: nil,
            source: .pane(.init(paneId: childPaneId)),
            isRead: false,
            isDismissedFromPaneInbox: false
        )

        presenter.recordRowActivation(notification: notification, paneIds: [parentPaneId, childPaneId])

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        await assertEventuallyMain("pane inbox presenter should write row activation trace") {
            (try? String(contentsOf: outputFileURL, encoding: .utf8))?
                .contains("\"body\":\"paneInbox.rowActivation\"") == true
        }

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.action.name\":\"focusPane\""))
        #expect(contents.contains("\"agentstudio.notification.id\":\"\(notification.id.uuidString)\""))
        #expect(contents.contains("\"agentstudio.notification.kind\":\"agentRpc\""))
        #expect(contents.contains("\"agentstudio.pane.id\":\"\(childPaneId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.pane.parent_id\":\"\(parentPaneId.uuidString)\""))
        #expect(contents.contains("\"agentstudio.pane.scope_count\":2"))
    }
}
