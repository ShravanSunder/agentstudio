import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Review viewer source structure', () => {
	test('keeps review data controllers outside the lazy visual shell boundary', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const shellBoundarySource = readSource('../app/bridge-app-review-viewer-shell-boundary.tsx');

		expect(modeSource).toContain('useBridgeReviewViewerStore');
		expect(modeSource).toContain('useBridgeReviewControlEventListeners');
		expect(modeSource).toContain('useBridgeReviewContentIdentityController');
		expect(modeSource).toContain('useBridgeReviewIntakeController');
		expect(modeSource).toContain('useBridgeReviewMetadataInterestRuntime');
		expect(modeSource).toContain('useBridgeReviewNavigationController');
		expect(modeSource).toContain('useBridgeReviewDemandTelemetryController');
		expect(modeSource).toContain('useBridgeReviewProjectionCoordinator');
		expect(modeSource).toContain('useBridgeReviewSelectionController');
		expect(modeSource).toContain('BridgeReviewViewerShellBoundary');
		expect(modeSource).not.toContain('useBridgeReviewVisibleContentController');
		expect(modeSource).not.toContain('LazyReviewViewerShell');
		expect(modeSource).not.toContain('<Suspense');

		expect(shellBoundarySource).toContain('LazyReviewViewerShell');
		expect(shellBoundarySource).toContain('<Suspense');
		expect(shellBoundarySource).not.toContain('useBridgeReviewIntakeController');
		expect(shellBoundarySource).not.toContain('useBridgeReviewMetadataInterestRuntime');
		expect(shellBoundarySource).not.toContain('useBridgeReviewProjectionCoordinator');
		expect(shellBoundarySource).not.toContain('useSelectedReviewContentDemandController');
		expect(shellBoundarySource).not.toContain('useBridgeReviewSelectedContentEffect');
	});

	test('keeps Review control event listeners in an app-level hook', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const hookSource = readSource('../app/use-bridge-review-control-event-listeners.ts');

		expect(modeSource).toContain('useBridgeReviewControlEventListeners');
		expect(modeSource).not.toContain('__bridge_select_review_item');
		expect(modeSource).not.toContain('__bridge_review_control');
		expect(modeSource).not.toContain('bridgeAppControlCommandSchema');
		expect(modeSource).not.toContain('applyBridgeAppControlCommand');

		expect(hookSource).toContain('__bridge_select_review_item');
		expect(hookSource).toContain('__bridge_review_control');
		expect(hookSource).toContain('bridgeAppControlCommandSchema');
		expect(hookSource).toContain('applyBridgeAppControlCommand');
		expect(hookSource).not.toContain('BridgeReviewViewerShellBoundary');
		expect(hookSource).not.toContain('@pierre/');
		expect(hookSource).not.toContain('useBridgeReviewViewerStore');
		expect(hookSource).not.toContain('AbortController');
		expect(hookSource).not.toContain('resourceExecutor');
		expect(hookSource).not.toContain('reviewDemandScheduler');
	});

	test('cuts selected Review away from FE package-first selected resources', () => {
		expect(sourceFileExists('../app/bridge-app-review-selected-content-controller.ts')).toBe(false);
		const forbiddenOwners = [
			'../app/bridge-app-review-controller.ts',
			'../app/bridge-app-review-viewer-mode.tsx',
			'../app/bridge-app-review-selected-content-controller.ts',
			'../app/bridge-app-review-markdown-preview-controller.ts',
			'../app/use-bridge-review-control-event-listeners.ts',
			'../app/bridge-app-control-commands.ts',
			'../app/bridge-app-review-telemetry-controller.ts',
		].flatMap((relativePath): string[] => {
			const source = readOptionalSource(relativePath);
			return [
				'useBridgeReviewSelectedContentEffect',
				'useSelectedReviewContentDemandController',
				'startSelectedReviewContentDemand',
				'selectedContentResourcesForCurrentSelection',
				'selectedContentResourcesState',
				'loadReviewItemContentResourcesThroughDemandResult',
				'readonly selectedContentResources: BridgeCodeViewContentResources | null',
				'selectedContentResources,',
				'resources: selectedContentResources',
			]
				.filter((token): boolean => source.includes(token))
				.map((token): string => `${relativePath}: ${token}`);
		});

		expect(forbiddenOwners).toEqual([]);
	});

	test('keeps Review selection orchestration in an app-level controller hook', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const selectionControllerSource = readSource(
			'../app/bridge-app-review-selection-controller.ts',
		);

		expect(modeSource).toContain('useBridgeReviewSelectionController');
		expect(modeSource).not.toContain('pendingSelectionCommitTelemetryRef');
		expect(modeSource).not.toContain('lastTelemetryMarkedItemRef');
		expect(modeSource).not.toContain('review.markFileViewed');
		expect(modeSource).not.toContain('recordReviewStartupTelemetry({');

		expect(selectionControllerSource).toContain('useBridgeReviewSelectionController');
		expect(selectionControllerSource).toContain('pendingSelectionCommitTelemetryRef');
		expect(selectionControllerSource).toContain('lastTelemetryMarkedItemRef');
		expect(selectionControllerSource).toContain('review.markFileViewed');
		expect(selectionControllerSource).toContain('recordReviewStartupTelemetry({');
		expect(selectionControllerSource).not.toContain('BridgeReviewViewerShellBoundary');
		expect(selectionControllerSource).not.toContain('useBridgeReviewViewerStore');
		expect(selectionControllerSource).not.toContain('createBridgeReviewProjectionWebWorkerClient');
		expect(selectionControllerSource).not.toContain('createBridgeMarkdownRenderWebWorkerClient');
		expect(selectionControllerSource).not.toContain('@pierre/');
	});

	test('routes Review selection and viewport display facts through the comm-worker render snapshot seam', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const renderSnapshotControllerSource = readSource(
			'../app/bridge-app-review-render-snapshot-controller.ts',
		);

		expect(modeSource).toContain('useBridgeReviewRenderSnapshotController');
		expect(modeSource).toContain('setSelectedReviewItemId');
		expect(modeSource).toContain('setReviewViewportItemIds');
		expect(modeSource).not.toContain('selectBridgeReviewSelectionSlice');
		expect(modeSource).not.toContain('selectBridgeReviewViewportSlice');
		expect(modeSource).not.toContain('viewerActions.setMountedItemIds');
		expect(renderSnapshotControllerSource).toContain('createBridgeMainRenderSnapshotStore');
		expect(renderSnapshotControllerSource).toContain(
			'createBridgeReviewCommWorkerTransportDispatcher',
		);
		expect(renderSnapshotControllerSource).not.toContain(
			'registerBridgeCommWorkerRuntimePortProtocol',
		);
		expect(renderSnapshotControllerSource).not.toContain('createBridgeReviewRuntimeProtocolPort');
		expect(renderSnapshotControllerSource).not.toContain('createBridgeCommWorkerCommandHandler');
		expect(renderSnapshotControllerSource).not.toContain('.handleMessage(');
		expect(renderSnapshotControllerSource).toContain('useSyncExternalStore');
		expect(renderSnapshotControllerSource).toContain('bridgeWorkerPierreRenderPolicy');
		expect(renderSnapshotControllerSource).not.toContain('maxBytes: 512 * 1024');
		expect(renderSnapshotControllerSource).not.toContain('maxWindowLines: 400');
		expect(renderSnapshotControllerSource).toContain('encodeBridgeWorkerSelectCommand');
		expect(renderSnapshotControllerSource).toContain('encodeBridgeWorkerViewportCommand');
		const viewportSetterSource = renderSnapshotControllerSource.slice(
			renderSnapshotControllerSource.indexOf('const setReviewViewportItemIds = useCallback'),
			renderSnapshotControllerSource.indexOf('return {'),
		);
		expect(viewportSetterSource).toContain('renderSnapshotStore.setLocalViewport');
		expect(viewportSetterSource).toContain('runtimeDispatcher.dispatch');
		expect(viewportSetterSource.indexOf('renderSnapshotStore.setLocalViewport')).toBeLessThan(
			viewportSetterSource.indexOf('runtimeDispatcher.dispatch'),
		);
	});

	test('removes the temporary no-courier selected loading shim from Review runtime', () => {
		const bridgeAppSource = readSource('../app/bridge-app.tsx');
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const selectionStateSource = readSource('../app/bridge-app-review-selection-state.ts');
		const renderSnapshotControllerSource = readSource(
			'../app/bridge-app-review-render-snapshot-controller.ts',
		);
		const runtimeProtocolSource = readSource(
			'../core/comm-worker/bridge-comm-worker-runtime-protocol.ts',
		);
		const commandHandlerSource = readSource(
			'../core/comm-worker/bridge-comm-worker-command-handler.ts',
		);
		const storeSource = readSource('../core/comm-worker/bridge-comm-worker-store.ts');
		const sourceByOwner = [
			['bridge-app.tsx', bridgeAppSource],
			['bridge-app-review-viewer-mode.tsx', modeSource],
			['bridge-app-review-selection-state.ts', selectionStateSource],
			['bridge-app-review-render-snapshot-controller.ts', renderSnapshotControllerSource],
			['bridge-comm-worker-runtime-protocol.ts', runtimeProtocolSource],
			['bridge-comm-worker-command-handler.ts', commandHandlerSource],
			['bridge-comm-worker-store.ts', storeSource],
		] as const;
		const forbiddenShimOwners = sourceByOwner.flatMap(([owner, source]): string[] =>
			[
				'selectedContentAvailabilityFromLegacySelectedContentState',
				'setSelectedContentAvailability',
				'applyLegacySelectedContentAvailabilityToMainRenderSnapshotStore',
				'selectedContentLoadingAvailabilityEnabled',
				'selectedContentPreparationEnabled',
				'selectedLoadingAvailabilityEnabled',
				'selectedPreparationAvailable',
			]
				.filter((token): boolean => source.includes(token))
				.map((token): string => `${owner}: ${token}`),
		);

		expect(forbiddenShimOwners).toEqual([]);
	});

	test('keeps Review navigation reconciliation in an app-level controller hook', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const navigationControllerSource = readSource(
			'../app/bridge-app-review-navigation-controller.ts',
		);

		expect(modeSource).toContain('useBridgeReviewNavigationController');
		expect(modeSource).not.toContain('appliedNavigationCommandRef');
		expect(modeSource).not.toContain('projection.orderedItemIds.includes(');
		expect(modeSource).not.toContain('clearReviewRefinementsHidingExplicitTarget(');

		expect(navigationControllerSource).toContain('useBridgeReviewNavigationController');
		expect(navigationControllerSource).toContain('appliedNavigationCommandRef');
		expect(navigationControllerSource).toContain('projection.orderedItemIds.includes(');
		expect(navigationControllerSource).toContain('clearReviewRefinementsHidingExplicitTarget(');
		expect(navigationControllerSource).not.toContain('BridgeReviewViewerShellBoundary');
		expect(navigationControllerSource).not.toContain('resourceExecutor');
		expect(navigationControllerSource).not.toContain('reviewDemandScheduler');
		expect(navigationControllerSource).not.toContain('createBridgeReviewProjectionWebWorkerClient');
		expect(navigationControllerSource).not.toContain('@pierre/');
	});

	test('keeps Review demand telemetry package filtering in an app-level controller hook', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const demandTelemetryControllerSource = readSource(
			'../app/bridge-app-review-demand-telemetry-controller.ts',
		);

		expect(modeSource).toContain('useBridgeReviewDemandTelemetryController');
		expect(modeSource).not.toContain('reviewContentDemandTelemetryForPackage');

		expect(demandTelemetryControllerSource).toContain('useBridgeReviewDemandTelemetryController');
		expect(demandTelemetryControllerSource).toContain('reviewContentDemandTelemetryForPackage');
		expect(demandTelemetryControllerSource).not.toContain('BridgeReviewViewerShellBoundary');
		expect(demandTelemetryControllerSource).not.toContain('useBridgeReviewViewerStore');
		expect(demandTelemetryControllerSource).not.toContain('createBridgeReviewViewerStore');
		expect(demandTelemetryControllerSource).not.toContain('resourceExecutor');
		expect(demandTelemetryControllerSource).not.toContain('reviewDemandScheduler');
		expect(demandTelemetryControllerSource).not.toContain('@pierre/');
	});

	test('keeps Review content registry identity in an app-level controller hook', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const contentIdentityControllerSource = readSource(
			'../app/bridge-app-review-content-identity-controller.ts',
		);

		expect(modeSource).toContain('useBridgeReviewContentIdentityController');
		expect(modeSource).not.toContain('contentRegistry.setActiveIdentity');

		expect(contentIdentityControllerSource).toContain('useBridgeReviewContentIdentityController');
		expect(contentIdentityControllerSource).toContain('contentRegistry.setActiveIdentity');
		expect(contentIdentityControllerSource).not.toContain('BridgeReviewViewerShellBoundary');
		expect(contentIdentityControllerSource).not.toContain('useBridgeReviewViewerStore');
		expect(contentIdentityControllerSource).not.toContain('createBridgeReviewViewerStore');
		expect(contentIdentityControllerSource).not.toContain('resourceExecutor');
		expect(contentIdentityControllerSource).not.toContain('reviewDemandScheduler');
		expect(contentIdentityControllerSource).not.toContain(
			'createBridgeReviewProjectionWebWorkerClient',
		);
		expect(contentIdentityControllerSource).not.toContain(
			'createBridgeMarkdownRenderWebWorkerClient',
		);
		expect(contentIdentityControllerSource).not.toContain('@pierre/');
	});

	test('cuts Review CodeView away from FE visible content hydration and expanded demand', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const shellBoundarySource = readSource('../app/bridge-app-review-viewer-shell-boundary.tsx');
		const reviewShellSource = readSource('./shell/review-viewer-shell.tsx');
		const codeViewPanelSource = readSource('./code-view/bridge-code-view-panel.tsx');
		const codeViewPanelTypesSource = readSource('./code-view/bridge-code-view-panel-types.ts');
		const codeViewPanelSupportSource = readSource('./code-view/bridge-code-view-panel-support.tsx');
		const visibleContentControllerSource = readOptionalSource(
			'../app/bridge-app-review-visible-content-controller.ts',
		);

		const forbiddenLiveTokens = (
			[
				[modeSource, 'useBridgeReviewVisibleContentController'],
				[modeSource, 'visibleContentResourcesByItemId='],
				[modeSource, 'onCodeViewExpandedItemDemand='],
				[shellBoundarySource, 'visibleContentResourcesByItemId'],
				[shellBoundarySource, 'onCodeViewExpandedItemDemand'],
				[reviewShellSource, 'visibleContentResourcesByItemId'],
				[reviewShellSource, 'onCodeViewExpandedItemDemand'],
				[codeViewPanelSource, 'visibleContentResourcesByItemId'],
				[codeViewPanelSource, 'onExpandedItemDemand'],
				[codeViewPanelTypesSource, 'visibleContentResourcesByItemId'],
				[codeViewPanelTypesSource, 'onExpandedItemDemand'],
				[codeViewPanelSupportSource, 'bridgeCodeViewMaterializationResourceEntriesForPanel'],
				[visibleContentControllerSource, 'useBridgeReviewVisibleContentController'],
				[visibleContentControllerSource, 'useVisibleReviewContentHydration'],
				[visibleContentControllerSource, 'loadReviewItemContentResourcesThroughDemandResult'],
				[visibleContentControllerSource, 'shouldPauseVisibleReviewContentHydration'],
				[visibleContentControllerSource, 'requestForegroundItemContent'],
			] satisfies ReadonlyArray<readonly [string, string]>
		).flatMap(([source, token]): string[] => (source.includes(token) ? [token] : []));

		expect(forbiddenLiveTokens).toEqual([]);
	});

	test('keeps Review selected display loading on worker availability slices', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const selectedLoadingSource = modeSource.slice(
			modeSource.indexOf(
				'const selectedCanvasLoadingReason = selectedCanvasLoadingReasonForCurrentSelection',
			),
			modeSource.indexOf('const selectedContentLoadingItemId'),
		);
		const unavailablePathSource = modeSource.slice(
			modeSource.indexOf(
				'selectedContentUnavailablePath={selectedContentUnavailablePathForCurrentSelection',
			),
			modeSource.indexOf('selectedItemPresentation={selectedItemPresentation}'),
		);

		expect(selectedLoadingSource).toContain('selectedContentAvailability');
		expect(selectedLoadingSource).not.toContain('selectedContentResourcesState');
		expect(unavailablePathSource).toContain('selectedContentAvailability');
		expect(unavailablePathSource).not.toContain('selectedContentResourcesState');
	});

	test('selected Review CodeView consumes worker-prepared items without FE selected content resources', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const shellBoundarySource = readSource('../app/bridge-app-review-viewer-shell-boundary.tsx');
		const shellSource = readSource('./shell/review-viewer-shell.tsx');
		const codeViewPanelTypesSource = readSource('./code-view/bridge-code-view-panel-types.ts');
		const codeViewPanelSource = readSource('./code-view/bridge-code-view-panel.tsx');

		expect(modeSource).toContain('selectedCodeViewItem');
		expect(modeSource).not.toContain('shouldLoadSelectedContent');
		expect(modeSource).not.toContain('selectedContentResources={selectedContentResources}');
		expect(shellBoundarySource).toContain('selectedCodeViewItem');
		expect(shellBoundarySource).not.toContain(
			'readonly selectedContentResources: BridgeCodeViewContentResources | null;',
		);
		expect(shellSource).toContain('selectedCodeViewItem');
		expect(shellSource).not.toContain(
			'readonly selectedContentResources?: BridgeCodeViewContentResources | null;',
		);
		expect(codeViewPanelTypesSource).toContain('readonly selectedCodeViewItem?');
		expect(codeViewPanelTypesSource).not.toContain(
			'readonly selectedContentResources?: BridgeCodeViewContentResources | null;',
		);
		expect(codeViewPanelSource).not.toContain(
			'selectedContentResources: props.selectedContentResources',
		);
	});

	test('selected review path does not schedule FE retry after descriptor registration', () => {
		const forbiddenRetryOwners = [
			'../app/bridge-app-review-viewer-mode.tsx',
			'../app/bridge-app-review-selected-content-controller.ts',
			'../app/bridge-app-review-selection-state.ts',
		].flatMap((relativePath): string[] => {
			const source = readOptionalSource(relativePath);
			return [
				'selectedContentRetryVersion',
				'selectedContentRetryScheduledRef',
				'scheduleSelectedContentRetry',
				'shouldRetrySelectedReviewContentAfterDescriptorRegistration',
				'retrySelectedContentAfterDescriptorRegistration',
			]
				.filter((token): boolean => source.includes(token))
				.map((token): string => `${relativePath}: ${token}`);
		});

		expect(forbiddenRetryOwners).toEqual([]);
	});

	test('keeps the review store out of content bodies and runtime handles', () => {
		const storeSource = readSource('./state/review-viewer-store.ts');

		expect(storeSource).toContain('rootSnapshot');
		expect(storeSource).toContain('projection');
		expect(storeSource).not.toContain('reviewPackage');
		expect(storeSource).not.toContain('contentRegistry');
		expect(storeSource).not.toContain('descriptorRegistry');
		expect(storeSource).not.toContain('resourceExecutor');
		expect(storeSource).not.toContain('AbortController');
		expect(storeSource).not.toContain('CodeViewHandle');
		expect(storeSource).not.toContain('useFileTree');
		expect(storeSource).not.toContain('@pierre/');
	});

	test('keeps Pierre imports out of review mode, shell boundary, and store surfaces', () => {
		const forbiddenPierreOwners = [
			'../app/bridge-app-review-viewer-mode.tsx',
			'../app/bridge-app-review-viewer-shell-boundary.tsx',
			'./state/review-viewer-store.ts',
			'./shell/review-viewer-shell.tsx',
		].filter((relativePath): boolean => readSource(relativePath).includes('@pierre/'));

		expect(forbiddenPierreOwners).toEqual([]);
	});

	test('keeps Review TypeScript and TSX files under one thousand lines', () => {
		const oversizedSources = readReviewViewerSourceFiles()
			.filter((entry): boolean => entry.lineCount > 1000)
			.map((entry): string => `${entry.relativePath}: ${entry.lineCount}`);

		expect(oversizedSources).toEqual([]);
		expect(
			readSource('../app/bridge-app-review-demand-telemetry-controller.ts').split('\n').length,
		).toBeLessThanOrEqual(1000);
		expect(
			readSource('../app/bridge-app-review-content-identity-controller.ts').split('\n').length,
		).toBeLessThanOrEqual(1000);
	});
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}

function readOptionalSource(relativePath: string): string {
	const sourcePath = fileURLToPath(new URL(relativePath, import.meta.url));
	return existsSync(sourcePath) ? readFileSync(sourcePath, 'utf8') : '';
}

function sourceFileExists(relativePath: string): boolean {
	return existsSync(fileURLToPath(new URL(relativePath, import.meta.url)));
}

function readReviewViewerSourceFiles(): readonly {
	readonly lineCount: number;
	readonly relativePath: string;
}[] {
	const rootPath = fileURLToPath(new URL('./', import.meta.url));
	return readSourceEntries(rootPath, '');
}

function readSourceEntries(
	absoluteDirectoryPath: string,
	relativeDirectoryPath: string,
): readonly { readonly lineCount: number; readonly relativePath: string }[] {
	return readdirSync(absoluteDirectoryPath, { withFileTypes: true }).flatMap((entry) => {
		const relativePath = join(relativeDirectoryPath, entry.name);
		const absolutePath = join(absoluteDirectoryPath, entry.name);
		if (entry.isDirectory()) {
			return readSourceEntries(absolutePath, relativePath);
		}
		if (!entry.isFile() || (!entry.name.endsWith('.ts') && !entry.name.endsWith('.tsx'))) {
			return [];
		}
		return [
			{
				relativePath,
				lineCount: readFileSync(absolutePath, 'utf8').split('\n').length,
			},
		];
	});
}
