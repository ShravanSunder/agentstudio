import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Pane context bounds")
struct PaneContextBoundsTests {
    @Test(
        "Message body bounds use UTF-8 bytes, and refusal leaves no message",
        arguments: [String(repeating: "x", count: 4097), String(repeating: "🛰", count: 1025)])
    func oversizedBodyHasNoEffect(body: String) async throws {
        try await withPaneContextService { fixture, service in
            let before = try await fixture.detail(service)

            #expect(await service.send(fixture.message(body: body)) == .refused(.tooLarge(.body)))

            #expect(try await fixture.detail(service) == before)
        }
    }

    @Test("The exact body byte limit is accepted")
    func exactBodyLimitIsAccepted() async throws {
        try await withPaneContextService { fixture, service in
            let request = fixture.message(body: String(repeating: "x", count: 4096))
            try await fixture.sendCreated(request, to: service)
            #expect(try await fixture.detail(service).messages.first?.body == request.body)
        }
    }

    @Test(
        "Why, choice count, choice labels, schema and action limits are checked before writes",
        arguments: OversizedMessageField.allCases)
    func fieldBoundsHaveNoEffect(field: OversizedMessageField) async throws {
        try await withPaneContextService { fixture, service in
            let before = try await fixture.detail(service)
            let request = try field.request(fixture)

            #expect(await service.send(request) == .refused(.tooLarge(field.limit)))
            #expect(try await fixture.detail(service) == before)
        }
    }

    @Test("The thirty-third open ask is refused until one settles")
    func openAskCapacityIsBounded() async throws {
        try await withPaneContextService { fixture, service in
            var asks: [PaneMessageSendRequest] = []
            for _ in 0..<32 {
                let ask = fixture.ask()
                try await fixture.sendCreated(ask, to: service)
                asks.append(ask)
            }
            let extra = fixture.ask()
            let before = try await fixture.detail(service)
            #expect(await service.send(extra) == .refused(.tooLarge(.openAsks)))
            #expect(try await fixture.detail(service) == before)
            try #require(await service.dismiss(messageId: asks[0].messageId, paneId: fixture.paneId) == .done)

            try await fixture.sendCreated(extra, to: service)
        }
    }

    @Test("The two-hundred-first unread notice is refused, and only person-read frees capacity")
    func unreadNoticeCapacityPreservesReadOwnership() async throws {
        try await withPaneContextService { fixture, service in
            var notices: [PaneMessageSendRequest] = []
            for _ in 0..<200 {
                let notice = fixture.message()
                try await fixture.sendCreated(notice, to: service)
                notices.append(notice)
            }
            let extra = fixture.message()
            #expect(await service.send(extra) == .refused(.tooLarge(.unreadNotices)))
            _ = try await fixture.detail(service)
            #expect(await service.send(extra) == .refused(.tooLarge(.unreadNotices)))
            try #require(await service.markRead(messageId: notices[0].messageId, paneId: fixture.paneId) == .done)

            try await fixture.sendCreated(extra, to: service)
        }
    }

    @Test("Title bounds use bytes and preserve the previous value", arguments: [256, 257])
    func titleBoundary(bytes: Int) async throws {
        try await withPaneContextService { fixture, service in
            let epoch = try await fixture.epoch(service)
            let text = String(repeating: "x", count: bytes)

            let result = await service.setTitle(fixture.title(text, epoch: epoch, counter: 1))

            #expect(result == (bytes == 256 ? .applied : .refused(.tooLarge(.title))))
            #expect(try await fixture.detail(service).agentTitle == (bytes == 256 ? text : nil))
        }
    }

    @Test("Agent Line summary bounds are enforced before an ordered write commits", arguments: [200, 201])
    func lineSummaryBoundary(bytes: Int) async throws {
        try await withPaneContextService { fixture, service in
            let epoch = try await fixture.epoch(service, stream: .line)
            let summary = String(repeating: "x", count: bytes)

            #expect(
                await service.setLine(fixture.line(summary, epoch: epoch, counter: 1))
                    == (bytes == 200 ? .applied : .refused(.tooLarge(.agentLine))))
            #expect(try await fixture.detail(service).agentLine?.summary == (bytes == 200 ? summary : nil))
        }
    }
}

enum OversizedMessageField: CaseIterable, Sendable {
    case why
    case choices
    case label
    case properties
    case schemaBytes
    case actionCount
    case actionBytes

    var limit: PaneContextLimitField {
        switch self {
        case .why: .why
        case .choices: .choices
        case .label: .choiceLabel
        case .properties, .schemaBytes: .form
        case .actionCount, .actionBytes: .actions
        }
    }

    func request(_ fixture: PaneContextServiceFixture) throws -> PaneMessageSendRequest {
        switch self {
        case .why: return fixture.message(why: String(repeating: "x", count: 1025))
        case .choices:
            let choices = try (0..<13).map { AskChoice(id: try AskChoiceId("choice-\($0)"), label: "choice") }
            return fixture.ask(form: .choice(options: choices, allowsMultiple: false))
        case .label:
            return fixture.ask(
                form: .choice(
                    options: [AskChoice(id: try AskChoiceId("choice"), label: String(repeating: "x", count: 201))],
                    allowsMultiple: false))
        case .properties:
            let properties = (0..<17).map {
                ElicitationProperty(name: "property-\($0)", title: nil, description: nil, type: .boolean)
            }
            return fixture.ask(form: .elicitation(ElicitationSchema(properties: properties, required: [])))
        case .schemaBytes:
            let property = ElicitationProperty(
                name: "property", title: nil, description: String(repeating: "x", count: 8193), type: .boolean)
            return fixture.ask(form: .elicitation(ElicitationSchema(properties: [property], required: [])))
        case .actionCount: return fixture.message(actions: Array(repeating: .goToPane(fixture.paneId), count: 5))
        case .actionBytes:
            return fixture.message(actions: [.openFile(path: String(repeating: "x", count: 1025), line: nil)])
        }
    }
}
