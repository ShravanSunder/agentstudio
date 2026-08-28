import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation

extension AppDelegate: ShellCommandHandling {
    func canExecute(_ request: AppCommandExecutionRequest) -> Bool {
        if request.arguments == .noArguments {
            return canExecute(request.command)
        }
        guard atomStore != nil else { return false }
        switch (request.command, request.arguments) {
        case (.setRepoSidebarSortOrder, .repoSidebarSortOrder):
            return true
        default:
            return false
        }
    }

    func canExecute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder, .toggleSidebar, .filterSidebar,
            .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .signInGitHub, .signInGoogle, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarQuickOpen, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos:
            true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .zoomPane, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .editPaneNote, .copyCurrentPanePath, .openPullRequest,
            .updateRepositoryFacts, .removeRepo, .addRepoFavorite, .removeRepoFavorite,
            .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane,
            .setInboxGroupingNone,
            .newFloatingTerminal, .openWebview, .reloadBridgeWebView, .showViewer,
            .showBridgeReview, .showBridgeFiles,
            .setRepoSidebarSortOrder,
            .setInboxRowStateFilter, .setInboxContentMode,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab, .openNewTerminalInTab:
            false
        }
    }

    func execute(_ command: AppCommand) -> Bool {
        switch command {
        case .watchFolder:
            Task { await handleWatchFolderRequested() }
            return true
        case .updateRepositoryFacts:
            return false
        case .toggleSidebar:
            mainWindowController?.toggleSidebar()
            return true
        case .filterSidebar:
            mainWindowController?.showSidebarFilter()
            return true
        case .showInboxNotifications:
            return false
        case .toggleInboxNotificationSort:
            return false
        case .clearReadInboxNotifications:
            return false
        case .clearAllInboxNotifications:
            return false
        case .showWorktreeSidebar:
            mainWindowController?.showWorktreeSidebar()
            return true
        case .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab:
            return executeSidebarGroupingCommand(command) == .applied
        case .setRepoSidebarSortOrder:
            return false
        case .setInboxRowStateFilter, .setInboxContentMode:
            return false
        case .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane,
            .setInboxGroupingNone:
            return false
        case .newWindow:
            newWindow()
            return true
        case .closeWindow:
            closeWindow()
            return true
        case .showCommandBarEverything:
            showCommandBar(prefix: nil, context: "command bar")
            return true
        case .showCommandBarQuickOpen:
            showCommandBar(defaultRootScope: .quickOpen, context: "command bar (quick open)")
            return true
        case .showCommandBarCommands:
            showCommandBar(prefix: ">", context: "command bar (commands)")
            return true
        case .showCommandBarPanes:
            showCommandBar(prefix: "$", context: "command bar (panes)")
            return true
        case .showCommandBarRepos:
            showCommandBar(prefix: "#", context: "command bar (repos)")
            return true
        case .signInGitHub:
            handleSignInRequested(provider: .github)
            return true
        case .signInGoogle:
            handleSignInRequested(provider: .google)
            return true
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .zoomPane, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .editPaneNote, .copyCurrentPanePath, .openPullRequest,
            .removeRepo, .addRepoFavorite, .removeRepoFavorite, .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .showPaneInboxNotifications, .clearPaneInboxNotifications,
            .newFloatingTerminal, .openWebview, .reloadBridgeWebView, .showViewer,
            .showBridgeReview, .showBridgeFiles,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab, .openNewTerminalInTab:
            return false
        }
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        switch command {
        case .updateRepositoryFacts:
            return executeRepositoryFactUpdate(repoId: target, targetType: targetType)
        case .closeTab, .breakUpTab, .renameTab, .newTerminalInTab, .newTab, .undoCloseTab,
            .selectTab, .nextTab, .prevTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .closePane, .extractPaneToTab, .movePaneToTab, .focusPane, .scrollToBottom,
            .scrollPageUp, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .splitRight, .splitLeft, .equalizePanes,
            .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown,
            .focusNextPane, .focusPrevPane, .zoomPane, .minimizePane, .expandPane,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
            .focusPane6, .focusPane7, .focusPane8, .focusPane9,
            .switchArrangement, .previousArrangement, .nextArrangement, .cycleArrangement,
            .saveArrangement, .deleteArrangement, .renameArrangement,
            .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown,
            .focusDrawerPaneRight,
            .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4,
            .focusDrawerPane5, .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8,
            .focusDrawerPane9,
            .detachDrawerPane, .addDrawerPane, .toggleDrawer,
            .navigateDrawerPane, .closeDrawerPane,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder, .openPaneLocationInEditorMenu,
            .editPaneNote, .copyCurrentPanePath, .openPullRequest,
            .watchFolder, .removeRepo, .addRepoFavorite, .removeRepoFavorite,
            .openWorktree, .openWorktreeInPane,
            .toggleManagementLayer,
            .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit,
            .toggleSidebar, .showInboxNotifications, .toggleInboxNotificationSort,
            .clearReadInboxNotifications, .clearAllInboxNotifications,
            .showPaneInboxNotifications, .clearPaneInboxNotifications, .showWorktreeSidebar,
            .setRepoSidebarGroupingRepo, .setRepoSidebarGroupingPane, .setRepoSidebarGroupingTab,
            .setRepoSidebarSortOrder,
            .setInboxGroupingTab, .setInboxGroupingRepo, .setInboxGroupingPane, .setInboxGroupingNone,
            .setInboxRowStateFilter, .setInboxContentMode,
            .newFloatingTerminal, .newWindow, .closeWindow,
            .showCommandBarEverything, .showCommandBarQuickOpen, .showCommandBarCommands,
            .showCommandBarPanes, .showCommandBarRepos,
            .openWebview, .reloadBridgeWebView, .showViewer, .showBridgeReview, .showBridgeFiles,
            .openBridgeReviewInNewTab, .openBridgeFilesInNewTab, .signInGitHub, .signInGoogle,
            .filterSidebar, .openNewTerminalInTab:
            return false
        }
    }

    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        guard command == .updateRepositoryFacts else {
            return canExecute(command)
        }
        guard
            targetType == .repo,
            repositoryFactUpdateSource != nil,
            store?.repositoryTopologyAtom.repo(target) != nil
        else {
            return false
        }
        return repositoryFactUpdateTasksByRepoId[target] == nil
    }

    func cancelRepositoryFactUpdate(repoId: UUID) {
        repositoryFactUpdateTasksByRepoId[repoId]?.cancel()
        repoCache?.removeRepositoryFactUpdateProgress(for: repoId)
    }

    func cancelAllRepositoryFactUpdates() {
        for task in repositoryFactUpdateTasksByRepoId.values {
            task.cancel()
        }
        guard let repoCache else { return }
        for repoId in repositoryFactUpdateTasksByRepoId.keys {
            repoCache.removeRepositoryFactUpdateProgress(for: repoId)
        }
    }

    func waitForRepositoryFactUpdatesToSettle() async {
        let tasks = Array(repositoryFactUpdateTasksByRepoId.values)
        for task in tasks {
            await task.value
        }
    }

    func acknowledgePresentedRepositoryFactUpdate(repoId: UUID, attemptId: UUID) {
        guard
            repositoryFactUpdateTasksByRepoId[repoId] == nil,
            let progress = repoCache?.repositoryFactUpdateProgress(for: repoId),
            progress.attemptId == attemptId,
            progress.phase == .settled
        else { return }
        repoCache.removeRepositoryFactUpdateProgress(for: repoId)
    }

    private func executeRepositoryFactUpdate(repoId: UUID, targetType: SearchItemType) -> Bool {
        guard
            canExecute(.updateRepositoryFacts, target: repoId, targetType: targetType),
            let repository = store.repositoryTopologyAtom.repo(repoId),
            let repositoryFactUpdateSource
        else {
            return false
        }

        do {
            try atomStore.core.applicationEntityRecency.recordOpened(
                repositoryStableKey: repository.stableKey,
                worktreeStableKeys: repository.worktrees.map(\.stableKey),
                at: Date()
            )
        } catch {
            return false
        }

        let attemptId = UUIDv7.generate()
        repoCache.setRepositoryFactUpdateProgress(
            .captured(repoId: repoId, attemptId: attemptId)
        )
        recordRepositoryFactUpdateProgress(
            .captured(repoId: repoId, attemptId: attemptId),
            stage: "captured"
        )
        repositoryFactUpdateTasksByRepoId[repoId] = Task { @MainActor [weak self, repositoryFactUpdateSource] in
            let admission = await repositoryFactUpdateSource.startRepositoryFactUpdate(
                repoId: repoId,
                attemptId: attemptId
            )
            guard self?.isCurrentRepositoryFactUpdate(repoId: repoId, attemptId: attemptId) == true else {
                _ = await admission.settlement()
                self?.finishRepositoryFactUpdateTask(repoId: repoId, attemptId: attemptId)
                return
            }

            let admittedProgress = RepositoryFactUpdateProgress.admitted(
                repoId: repoId,
                attemptId: attemptId,
                applicableSources: admission.acceptedSources,
                terminalResultsBySource: admission.terminalResultsBySource
            )
            if !admission.acceptedSources.isEmpty {
                self?.repoCache.setRepositoryFactUpdateProgress(admittedProgress)
            }
            self?.recordRepositoryFactUpdateProgress(admittedProgress, stage: "admitted")
            let outcomesBySource = await admission.settlement()
            guard let self else { return }
            if self.isCurrentRepositoryFactUpdate(repoId: repoId, attemptId: attemptId) {
                self.finishRepositoryFactUpdateTask(repoId: repoId, attemptId: attemptId)
                let settledProgress = admittedProgress.settled(outcomesBySource)
                self.repoCache.setRepositoryFactUpdateProgress(settledProgress)
                self.recordRepositoryFactUpdateProgress(settledProgress, stage: "settled")
                return
            }
            self.finishRepositoryFactUpdateTask(repoId: repoId, attemptId: attemptId)
        }
        return true
    }

    private func recordRepositoryFactUpdateProgress(
        _ progress: RepositoryFactUpdateProgress,
        stage: String
    ) {
        let outcome: String
        switch progress.phase {
        case .captured: outcome = "captured"
        case .inProgress: outcome = "loading"
        case .settled: outcome = Self.repositoryFactUpdateSettlementOutcome(progress)
        }
        performanceTraceRecorder?.record(
            .repositoryFactUpdate,
            attributes: [
                "agentstudio.performance.repository_update.stage": .string(stage),
                "agentstudio.performance.repository_update.outcome": .string(outcome),
                "agentstudio.performance.repository_update.applicable_source.count": .int(
                    progress.applicableSources.count),
                "agentstudio.performance.repository_update.unsettled_source.count": .int(
                    progress.unsettledSources.count),
                "agentstudio.performance.repository_update.terminal_source.count": .int(
                    progress.settledResultsBySource.count),
            ]
        )
    }

    static func repositoryFactUpdateSettlementOutcome(
        _ progress: RepositoryFactUpdateProgress
    ) -> String {
        guard !progress.applicableSources.isEmpty else { return "no_applicable" }
        let applicableResults = progress.applicableSources.compactMap {
            progress.settledResultsBySource[$0]
        }
        guard applicableResults.count == progress.applicableSources.count else {
            return "incomplete"
        }
        let completedCount = applicableResults.count { $0 == .completed }
        if completedCount == applicableResults.count { return "complete" }
        if completedCount > 0 { return "partial_failure" }
        if applicableResults.contains(.failed) { return "failed" }
        if applicableResults.allSatisfy({ $0 == .cancelled }) { return "cancelled" }
        if applicableResults.allSatisfy({ $0 == .obsolete }) { return "obsolete" }
        return "mixed_terminal"
    }

    private func isCurrentRepositoryFactUpdate(repoId: UUID, attemptId: UUID) -> Bool {
        repoCache.repositoryFactUpdateProgress(for: repoId)?.attemptId == attemptId
    }

    private func finishRepositoryFactUpdateTask(repoId: UUID, attemptId: UUID) {
        guard
            repositoryFactUpdateTasksByRepoId[repoId] != nil,
            repoCache.repositoryFactUpdateProgress(for: repoId)?.attemptId == attemptId
                || repoCache.repositoryFactUpdateProgress(for: repoId) == nil
        else {
            return
        }
        repositoryFactUpdateTasksByRepoId.removeValue(forKey: repoId)
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        switch (request.command, request.arguments) {
        case (.showWorktreeSidebar, .noArguments) where request.executionContext == .headlessIPC:
            return executeHeadlessRepoSidebarCommand()
        case (.setRepoSidebarSortOrder, .repoSidebarSortOrder(let order)):
            return executeRepoSidebarSortOrderCommand(order)
        case (.setRepoSidebarGroupingRepo, .noArguments), (.setRepoSidebarGroupingPane, .noArguments),
            (.setRepoSidebarGroupingTab, .noArguments):
            return executeSidebarGroupingCommand(request.command)
        case (.showInboxNotifications, _), (.toggleInboxNotificationSort, _),
            (.clearReadInboxNotifications, _), (.clearAllInboxNotifications, _),
            (.showPaneInboxNotifications, _), (.clearPaneInboxNotifications, _),
            (.setInboxGroupingTab, _), (.setInboxGroupingRepo, _),
            (.setInboxGroupingPane, _), (.setInboxGroupingNone, _),
            (.setInboxRowStateFilter, _), (.setInboxContentMode, _):
            return .unsupportedCommand
        default:
            return execute(request.command) ? .applied : .unsupportedCommand
        }
    }

    private func executeSidebarGroupingCommand(_ command: AppCommand) -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        switch command {
        case .setRepoSidebarGroupingRepo:
            atomStore.repoExplorerSidebarPrefs.setGroupingMode(.repo)
            return atomStore.repoExplorerSidebarPrefs.groupingMode == .repo ? .applied : .stateUnavailable
        case .setRepoSidebarGroupingPane:
            atomStore.repoExplorerSidebarPrefs.setGroupingMode(.pane)
            return atomStore.repoExplorerSidebarPrefs.groupingMode == .pane ? .applied : .stateUnavailable
        case .setRepoSidebarGroupingTab:
            atomStore.repoExplorerSidebarPrefs.setGroupingMode(.tab)
            return atomStore.repoExplorerSidebarPrefs.groupingMode == .tab ? .applied : .stateUnavailable
        default:
            return .unsupportedCommand
        }
    }

    private func executeHeadlessRepoSidebarCommand() -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.core.workspaceSidebarState.setSidebarSurface(.repos)
        mainWindowController?.expandSidebar()
        guard
            atomStore.core.workspaceSidebarState.sidebarSurface == .repos,
            atomStore.core.workspaceSidebarState.sidebarCollapsed == false
        else {
            return .stateUnavailable
        }
        return .applied
    }

    private func executeRepoSidebarSortOrderCommand(_ order: RepoExplorerSortOrder) -> AppCommandExecutionOutcome {
        guard let atomStore else { return .stateUnavailable }
        atomStore.repoExplorerSidebarPrefs.setSortOrder(order)
        guard atomStore.repoExplorerSidebarPrefs.sortOrder == order else {
            return .stateUnavailable
        }
        return .applied
    }
}
