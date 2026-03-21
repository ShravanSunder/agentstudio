import Foundation

enum TerminalRestoreFailureReason: Sendable, Equatable {
    case attachFailed(AttachError)
}

enum TerminalRestorePhase: Sendable, Equatable {
    case idle
    case waitingForTrustedGeometry
    case startingSurface
    case attachedHidden
    case attachedVisible
    case failed(TerminalRestoreFailureReason)
}

enum TerminalRestoreVisiblePresentation: Sendable, Equatable {
    case idle
    case restoring
    case placeholder
    case terminal
}

enum TerminalRestoreEvent: Sendable, Equatable {
    case beginRestore
    case geometryResolved(CGRect)
    case surfaceCreated
    case promotedToVisible
    case processHealthChecked(alive: Bool)
    case attachFailed(AttachError)
}

enum TerminalRestoreEffect: Sendable, Equatable {
    case startSurface
}

struct TerminalRestoreState: MachineState {
    typealias Event = TerminalRestoreEvent
    typealias Effect = TerminalRestoreEffect

    let phase: TerminalRestorePhase
    let isVisible: Bool

    init(
        phase: TerminalRestorePhase = .idle,
        isVisible: Bool = false
    ) {
        self.phase = phase
        self.isVisible = isVisible
    }

    var visiblePresentation: TerminalRestoreVisiblePresentation {
        switch phase {
        case .idle, .waitingForTrustedGeometry:
            return .idle
        case .startingSurface:
            return isVisible ? .restoring : .idle
        case .attachedHidden, .attachedVisible:
            return .terminal
        case .failed:
            return .placeholder
        }
    }

    static func transition(
        from state: Self,
        on event: TerminalRestoreEvent
    ) -> Transition<Self, TerminalRestoreEffect> {
        switch (state.phase, event) {
        case (.idle, .beginRestore):
            return Transition(
                Self(
                    phase: .waitingForTrustedGeometry,
                    isVisible: state.isVisible
                )
            )

        case (.waitingForTrustedGeometry, .geometryResolved):
            return Transition(
                Self(
                    phase: .startingSurface,
                    isVisible: state.isVisible
                ),
                effects: [.startSurface]
            )

        case (.startingSurface, .surfaceCreated):
            return Transition(state)

        case (.startingSurface, .processHealthChecked(let alive)):
            if alive {
                return Transition(
                    Self(
                        phase: state.isVisible ? .attachedVisible : .attachedHidden,
                        isVisible: state.isVisible
                    )
                )
            }

            return Transition(
                Self(
                    phase: .failed(.attachFailed(.timeout)),
                    isVisible: state.isVisible
                )
            )

        case (.waitingForTrustedGeometry, .promotedToVisible):
            return Transition(
                Self(
                    phase: .waitingForTrustedGeometry,
                    isVisible: true
                )
            )

        case (.startingSurface, .promotedToVisible):
            return Transition(
                Self(
                    phase: .startingSurface,
                    isVisible: true
                )
            )

        case (.attachedHidden, .promotedToVisible):
            return Transition(
                Self(
                    phase: .attachedVisible,
                    isVisible: true
                )
            )

        case (_, .attachFailed(let error)):
            return Transition(
                Self(
                    phase: .failed(.attachFailed(error)),
                    isVisible: state.isVisible
                )
            )

        default:
            return Transition(state)
        }
    }
}
