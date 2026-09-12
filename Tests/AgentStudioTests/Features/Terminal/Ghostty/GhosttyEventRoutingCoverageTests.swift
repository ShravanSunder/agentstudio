import Foundation
import GhosttyKit
import Testing

@testable import AgentStudioTerminal

@Suite("Ghostty event routing coverage", .serialized)
@MainActor
struct GhosttyEventRoutingCoverageTests {
    @Test("upstream action vocabulary has no unmapped values")
    func upstreamActionVocabularyHasNoUnmappedValues() throws {
        let header = try String(contentsOfFile: "vendor/ghostty/include/ghostty.h", encoding: .utf8)
        let enumEnd = try #require(header.range(of: "} ghostty_action_tag_e;"))
        let enumStart = try #require(header[..<enumEnd.lowerBound].range(of: "typedef enum {", options: .backwards))
        let entries = header[enumStart.upperBound..<enumEnd.lowerBound]
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Fail closed if upstream changes from implicit contiguous C enum values.
        for entry in entries {
            #expect(entry.range(of: "^GHOSTTY_ACTION_[A-Z0-9_]+$", options: .regularExpression) != nil)
        }
        let upstreamValues = Set(entries.indices.map { UInt32($0) })
        let localValues = GhosttyActionTag.allCases.map(\.rawValue)
        #expect(Set(localValues) == upstreamValues)
        #expect(localValues.count == Set(localValues).count)

        let mapping = try String(
            contentsOfFile: "Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionTag.swift", encoding: .utf8)
        let constants = try NSRegularExpression(pattern: "GHOSTTY_ACTION_[A-Z0-9_]+")
        let mappedNames = constants.matches(in: mapping, range: NSRange(mapping.startIndex..., in: mapping))
            .compactMap { Range($0.range, in: mapping).map { String(mapping[$0]) } }
        #expect(Set(mappedNames) == Set(entries))
        #expect(mappedNames.count == entries.count)
    }

    @Test(
        "unsupported upstream actions translate safely",
        arguments: [
            GhosttyActionTag.exportTerminalIO, .setWindowTitle, .selectionChanged, .moveTabToNewWindow,
        ])
    func unsupportedUpstreamActionsTranslateSafely(tag: GhosttyActionTag) {
        #expect(Ghostty.ActionRouter.unsupportedTags.contains(tag))
        #expect(GhosttyAdapter.shared.translate(actionTag: tag) == .unhandled(tag: tag.rawValue))
        #expect(GhosttyAdapter.shared.translate(actionTag: tag.rawValue) == .unhandled(tag: tag.rawValue))
    }

    @Test("every known Ghostty action tag has one explicit routing decision")
    func everyKnownGhosttyActionTag_hasExplicitRoutingDecision() {
        let accountedTags =
            Ghostty.ActionRouter.explicitlyRoutedTags
            .union(Ghostty.ActionRouter.deferredTags)
            .union(Ghostty.ActionRouter.interceptedTags)
            .union(Ghostty.ActionRouter.unsupportedTags)

        #expect(accountedTags == Set(GhosttyActionTag.allCases))
    }
}
