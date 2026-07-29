import Testing

@testable import AgentStudioCore

@Suite("App command presentation policy")
struct AppCommandPresentationPolicyTests {
    @Test("unsupported surfaces are rejected")
    func unsupportedSurfacesAreRejected() {
        let definition = makeDefinition(
            surfacePolicy: .exposed([.toolbar(.pane)]),
            targeting: .contextual
        )
        let context = CommandContext.empty

        #expect(
            definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .toolbar(.pane),
                    subject: .contextual(context)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .toolbar(.terminalZoom),
                    subject: .contextual(context)
                )
            )
        )
    }

    @Test("contextual presentation requires every visible requirement")
    func contextualPresentationRequiresEveryVisibleRequirement() {
        let definition = makeDefinition(
            surfacePolicy: .exposed([.commandBar]),
            targeting: .contextual,
            visibleWhen: [.hasActivePane, .paneIsTerminal]
        )
        let missingTerminalRequirement = CommandContext(
            satisfiedRequirements: [.hasActivePane]
        )
        let allRequirementsSatisfied = CommandContext(
            focusedContentType: .terminal,
            satisfiedRequirements: [.hasActivePane, .hasActiveTab]
        )

        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .commandBar,
                    subject: .contextual(missingTerminalRequirement)
                )
            )
        )
        #expect(
            definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .commandBar,
                    subject: .contextual(allRequirementsSatisfied)
                )
            )
        )
    }

    @Test("targeted presentation checks target kinds without conflating invocation mode")
    func targetedPresentationChecksTargetKindsWithoutConflatingInvocationMode() {
        let definition = makeDefinition(
            surfacePolicy: .exposed([.contextMenu]),
            targeting: .targeted([.pane, .tab]),
            visibleWhen: [.hasActivePane]
        )

        #expect(
            definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .contextMenu,
                    subject: .targeted(.pane)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .contextMenu,
                    subject: .targeted(.worktree)
                )
            )
        )
        #expect(
            definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .contextMenu,
                    subject: .contextual(CommandContext(satisfiedRequirements: [.hasActivePane]))
                )
            )
        )
    }

    @Test("contextual target presentation requires both context and target support")
    func contextualTargetPresentationRequiresContextAndTargetSupport() {
        let definition = makeDefinition(
            surfacePolicy: .exposed([.inlineControl]),
            targeting: .contextualAndTargeted(
                [.pane],
                preferredInvocation: .targetSelection
            ),
            visibleWhen: [.hasActivePane, .paneIsTerminal]
        )
        let missingTerminalRequirement = CommandContext(
            satisfiedRequirements: [.hasActivePane]
        )
        let allRequirementsSatisfied = CommandContext(
            focusedContentType: .terminal,
            satisfiedRequirements: [.hasActivePane]
        )

        #expect(
            definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .inlineControl,
                    subject: .contextualTarget(allRequirementsSatisfied, .pane)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .inlineControl,
                    subject: .contextualTarget(missingTerminalRequirement, .pane)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .inlineControl,
                    subject: .contextualTarget(allRequirementsSatisfied, .worktree)
                )
            )
        )
    }

    @Test("not-presented commands reject every presentation subject")
    func notPresentedCommandsRejectEveryPresentationSubject() {
        let definition = makeDefinition(
            surfacePolicy: .notPresented,
            targeting: .contextualAndTargeted(
                [.pane],
                preferredInvocation: .contextual
            )
        )
        let context = CommandContext.empty

        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .mainMenu,
                    subject: .contextual(context)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .mainMenu,
                    subject: .targeted(.pane)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .mainMenu,
                    subject: .contextualTarget(context, .pane)
                )
            )
        )
    }

    @Test("empty exposed surfaces and target sets are invalid")
    func emptyExposedSurfacesAndTargetSetsAreInvalid() {
        #expect(!AppCommandSurfacePolicy.exposed([]).isValid)
        #expect(!AppCommandTargeting.targeted([]).isValid)
        #expect(
            !AppCommandTargeting.contextualAndTargeted(
                [],
                preferredInvocation: .targetSelection
            ).isValid
        )
    }

    @Test("mutually exclusive content requirements cannot present")
    func mutuallyExclusiveContentRequirementsCannotPresent() {
        let definition = makeDefinition(
            surfacePolicy: .exposed([.commandBar]),
            targeting: .contextual,
            visibleWhen: [.paneIsTerminal, .paneIsBridge]
        )
        let terminalContext = CommandContext(
            focusedContentType: .terminal,
            satisfiedRequirements: [.paneIsBridge]
        )
        let bridgeContext = CommandContext(
            focusedContentType: .bridge,
            satisfiedRequirements: [.paneIsTerminal]
        )

        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .commandBar,
                    subject: .contextual(terminalContext)
                )
            )
        )
        #expect(
            !definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .commandBar,
                    subject: .contextual(bridgeContext)
                )
            )
        )
    }

    private func makeDefinition(
        surfacePolicy: AppCommandSurfacePolicy,
        targeting: AppCommandTargeting,
        visibleWhen: Set<CommandRequirement> = []
    ) -> AppCommandSpec {
        AppCommandSpec(
            command: .closePane,
            label: "Close Pane",
            icon: .system(.xmarkSquare),
            helpText: "Close the active pane",
            surfacePolicy: surfacePolicy,
            targeting: targeting,
            visibleWhen: visibleWhen
        )
    }
}
