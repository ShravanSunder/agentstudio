import Foundation

enum NonterminalContentMountFailure: Equatable, Sendable {
    case unsupportedContent(type: String, version: Int)
    case mountRejected
}

enum NonterminalContentMountAdmissionResult: Equatable, Sendable {
    case mounted
    case failed(NonterminalContentMountFailure)
}

enum NonterminalContentMountMemberState: Equatable, Sendable {
    case queued(priority: TerminalActivationVisibilityPriority)
    case mounting
    case mounted
    case failedNonterminal(NonterminalContentMountFailure)
    case cancelledReplaced(replacement: WorkspaceContentMountGeneration)
}

enum NonterminalContentMountOutcome: Equatable, Sendable {
    case mounted
    case failedNonterminal(NonterminalContentMountFailure)
    case cancelledReplaced(replacement: WorkspaceContentMountGeneration)
}

struct NonterminalContentMountSettlement: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let outcomesByPaneID: [PaneId: NonterminalContentMountOutcome]
}

@MainActor
protocol NonterminalContentMountAdmissionPort: AnyObject {
    func mount(_ descriptor: NonterminalContentMountDescriptor) -> NonterminalContentMountAdmissionResult
}

/// Bounded MainActor owner for one accepted nonterminal content cohort.
///
/// The owner consumes the immutable, already-prioritized input in one task. It
/// mounts at most the compile-time service quantum before yielding, so a large
/// workspace cannot become one unbroken MainActor turn. It never reads atoms,
/// repository topology, or persistence state.
@MainActor
final class NonterminalContentMountOwner {
    private enum Lifecycle {
        case idle
        case mounting
        case settled(NonterminalContentMountSettlement)
    }

    private let generation: WorkspaceContentMountGeneration
    private let entries: [NonterminalContentMountDescriptor]
    private let admissionPort: any NonterminalContentMountAdmissionPort
    private var lifecycle = Lifecycle.idle
    private var statesByPaneID: [PaneId: NonterminalContentMountMemberState]

    init(
        generation: WorkspaceContentMountGeneration,
        input: NonterminalContentMountInput,
        admissionPort: any NonterminalContentMountAdmissionPort
    ) {
        let paneIDs = input.entries.map(\.paneID)
        precondition(Set(paneIDs).count == paneIDs.count, "nonterminal content cohort contains duplicate panes")
        self.generation = generation
        entries = input.entries
        self.admissionPort = admissionPort
        statesByPaneID = Dictionary(
            uniqueKeysWithValues: input.entries.map {
                ($0.paneID, .queued(priority: $0.visibilityPriority))
            }
        )
    }

    func mount() async -> NonterminalContentMountSettlement {
        switch lifecycle {
        case .settled(let settlement):
            return settlement
        case .mounting:
            preconditionFailure("nonterminal content cohort mounted reentrantly")
        case .idle:
            lifecycle = .mounting
        }

        var mountsInCurrentTurn = 0
        for descriptor in entries {
            guard case .mounting = lifecycle else { break }
            guard case .queued = statesByPaneID[descriptor.paneID] else { continue }

            statesByPaneID[descriptor.paneID] = .mounting
            switch admissionPort.mount(descriptor) {
            case .mounted:
                statesByPaneID[descriptor.paneID] = .mounted
            case .failed(let failure):
                statesByPaneID[descriptor.paneID] = .failedNonterminal(failure)
            }

            mountsInCurrentTurn += 1
            if mountsInCurrentTurn == AppPolicies.NonterminalContentMount.maximumMountsPerMainActorTurn {
                mountsInCurrentTurn = 0
                await Task.yield()
            }
        }

        if case .settled(let replacementSettlement) = lifecycle {
            return replacementSettlement
        }
        let settlement = makeSettlement()
        lifecycle = .settled(settlement)
        return settlement
    }

    func cancelAndReplace(
        with replacement: WorkspaceContentMountGeneration
    ) -> NonterminalContentMountSettlement {
        precondition(replacement != generation, "replacement content generation must differ")
        for (paneID, state) in statesByPaneID {
            switch state {
            case .queued, .mounting:
                statesByPaneID[paneID] = .cancelledReplaced(replacement: replacement)
            case .mounted, .failedNonterminal, .cancelledReplaced:
                break
            }
        }
        let settlement = makeSettlement()
        lifecycle = .settled(settlement)
        return settlement
    }

    func memberState(for paneID: PaneId) -> NonterminalContentMountMemberState? {
        statesByPaneID[paneID]
    }

    private func makeSettlement() -> NonterminalContentMountSettlement {
        let outcomes = statesByPaneID.mapValues { state -> NonterminalContentMountOutcome in
            switch state {
            case .mounted:
                return .mounted
            case .failedNonterminal(let failure):
                return .failedNonterminal(failure)
            case .cancelledReplaced(let replacement):
                return .cancelledReplaced(replacement: replacement)
            case .queued, .mounting:
                preconditionFailure("nonterminal content cohort settled with unfinished members")
            }
        }
        return NonterminalContentMountSettlement(
            generation: generation,
            outcomesByPaneID: outcomes
        )
    }
}
