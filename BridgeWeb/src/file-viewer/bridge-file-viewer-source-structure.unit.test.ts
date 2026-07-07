import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge file viewer source structure', () => {
	test('keeps content body loading in the content controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const appPropsSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app-props.ts', import.meta.url)),
			'utf8',
		);
		const contentControllerSource = readFileSync(
			fileURLToPath(new URL('./use-bridge-file-viewer-content-controller.ts', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerContentController');
		expect(appSource).not.toContain('runtime.openFile');
		expect(appSource).not.toContain('runtime.refreshOpenFile');
		expect(appSource).not.toContain('useBridgeFileViewerBodyState');
		expect(appSource).not.toContain('openFileBodyRef');
		expect(appSource).not.toContain('clearOpenFileBody');
		expect(appSource).not.toContain('clearProvisionalOpenFileBody');
		expect(appSource).not.toContain('recordBridgeViewerFileOpenReadyTelemetrySample');
		expect(appPropsSource).not.toContain('fileViewCommWorkerTransportFactory');
		expect(contentControllerSource).not.toContain('runtime.openFile');
		expect(contentControllerSource).not.toContain('result.content.readText');
		expect(contentControllerSource).not.toContain('openFileBodyRef');
		expect(contentControllerSource).not.toContain('clearOpenFileBody');
		expect(contentControllerSource).not.toContain('clearProvisionalOpenFileBody');
	});

	test('keeps visible viewport demand dispatch in a controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const visibleDemandControllerSource = readFileSync(
			fileURLToPath(
				new URL('./use-bridge-file-viewer-visible-demand-controller.ts', import.meta.url),
			),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerVisibleDemandController');
		expect(appSource).not.toContain('visibleItemIds');
		expect(appSource).not.toContain('selectionSlice');
		expect(appSource).not.toContain('viewportSlice');
		expect(appSource).not.toContain('recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample');
		expect(appSource).not.toContain('runtime.dispatchDemandStimuli');
		expect(visibleDemandControllerSource).toContain('visibleItemIds');
		expect(visibleDemandControllerSource).not.toContain('runtime.dispatchDemandStimuli');
		expect(visibleDemandControllerSource).not.toContain('WorktreeFileDemandStimulus');
		expect(visibleDemandControllerSource).not.toContain('WorktreeFileSurfaceRuntime');
	});

	test('keeps recently-updated demand dispatch in its controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const recentlyUpdatedDemandSource = readFileSync(
			fileURLToPath(
				new URL('./use-bridge-file-viewer-recently-updated-demand.ts', import.meta.url),
			),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerRecentlyUpdatedDemand');
		expect(appSource).not.toContain('WorktreeFileDemandStimulus');
		expect(appSource).not.toContain('recentlyUpdatedFile');
		expect(appSource).not.toContain('dispatchRecentlyUpdatedDescriptorDemand');
		expect(appSource).not.toContain('dispatchPendingRecentlyUpdatedDescriptorDemand');
		expect(recentlyUpdatedDemandSource).toContain('bridgeFileViewerRecentlyUpdatedEventName');
		expect(recentlyUpdatedDemandSource).not.toContain('runtime.dispatchDemandStimuli');
		expect(recentlyUpdatedDemandSource).not.toContain('WorktreeFileDemandStimulus');
		expect(recentlyUpdatedDemandSource).not.toContain('WorktreeFileSurfaceRuntime');
	});

	test('keeps descriptor request replay logic in a controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const descriptorRequestControllerSource = readFileSync(
			fileURLToPath(
				new URL('./use-bridge-file-viewer-descriptor-request-controller.ts', import.meta.url),
			),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerDescriptorRequestController');
		expect(appSource).not.toContain('canFetchWorktreeFileDescriptorContent');
		expect(appSource).not.toContain('const openPendingSelectedDescriptor = useCallback');
		expect(appSource).not.toContain('const requestFileDescriptor = useCallback');
		expect(appSource).not.toContain('const requestFileDescriptorForDemand = useCallback');
		expect(descriptorRequestControllerSource).toContain('canFetchWorktreeFileDescriptorContent');
		expect(descriptorRequestControllerSource).toContain('openPendingSelectedDescriptor');
		expect(descriptorRequestControllerSource).toContain('requestFileDescriptor');
		expect(descriptorRequestControllerSource).toContain('requestFileDescriptorForDemand');
	});

	test('keeps the browser worker transport seam instance scoped', () => {
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
			'utf8',
		);
		const browserHarnessAppSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-browser-test-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(renderSnapshotControllerSource).toContain(
			'BridgeFileViewerRuntimeTransportFactoryProvider',
		);
		expect(renderSnapshotControllerSource).not.toContain(
			'bridgeFileViewerRuntimeTransportFactoryForTest',
		);
		expect(renderSnapshotControllerSource).not.toContain(
			'setBridgeFileViewerRuntimeTransportFactoryForTest',
		);
		expect(browserHarnessAppSource).toContain('BridgeFileViewerRuntimeTransportFactoryProvider');
		expect(browserHarnessAppSource).not.toContain(
			'setBridgeFileViewerRuntimeTransportFactoryForTest',
		);
	});

	test('keeps frame application out of the file viewer app coordinator', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerFrameIntakeController');
		expect(appSource).not.toContain('applyFramesToRuntime');
		expect(appSource).not.toContain('reconcileOpenFileStateWithFrames');
	});

	test('keeps File View frame intake free of the legacy fetch-capable runtime', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const stateSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-state.ts', import.meta.url)),
			'utf8',
		);
		const frameIntakeSource = readFileSync(
			fileURLToPath(
				new URL('./use-bridge-file-viewer-frame-intake-controller.ts', import.meta.url),
			),
			'utf8',
		);
		const legacyRuntimePath = fileURLToPath(
			new URL('./bridge-file-viewer-runtime.ts', import.meta.url),
		);

		expect(existsSync(legacyRuntimePath)).toBe(false);
		expect(appSource).not.toContain('createBridgeFileViewerRuntime');
		expect(appSource).not.toContain('WorktreeFileSurfaceRuntime');
		expect(frameIntakeSource).not.toContain('WorktreeFileSurfaceRuntime');
		expect(stateSource).not.toContain('defaultFetchWorktreeFileResource');
		expect(stateSource).not.toContain('loadBridgeTextResourceWithTiming');
	});

	test('keeps File View stale refresh retry ownership out of React', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const contentControllerSource = readFileSync(
			fileURLToPath(new URL('./use-bridge-file-viewer-content-controller.ts', import.meta.url)),
			'utf8',
		);
		const stateSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-state.ts', import.meta.url)),
			'utf8',
		);
		const worktreeSurfaceSource = readFileSync(
			fileURLToPath(new URL('../worktree-file-surface/worktree-file-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(appSource).not.toContain('staleAutoRefreshGuardRef');
		expect(appSource).not.toContain('staleAutoRefreshTimeoutRef');
		expect(appSource).not.toContain('pendingRefreshFailureHandlerRef');
		expect(contentControllerSource).not.toContain('setPendingRefreshFailureHandler');
		expect(contentControllerSource).not.toContain('onRefreshFailure');
		expect(stateSource).not.toContain('duplicate_stale_auto_refresh_failure');
		expect(worktreeSurfaceSource).not.toContain('setTimeout');
		expect(worktreeSurfaceSource).not.toContain('shouldAutoRefreshStaleOpenFile');
	});

	test('keeps Pierre runtime imports out of file viewer controller hooks', () => {
		const controllerHookUrls = [
			'./use-bridge-file-viewer-content-controller.ts',
			'./use-bridge-file-viewer-descriptor-request-controller.ts',
			'./use-bridge-file-viewer-frame-intake-controller.ts',
			'./use-bridge-file-viewer-recently-updated-demand.ts',
			'./use-bridge-file-viewer-visible-demand-controller.ts',
			'./use-bridge-file-viewer-shell-model.ts',
			'./use-bridge-file-viewer-store-bindings.ts',
		];

		for (const controllerHookUrl of controllerHookUrls) {
			const source = readFileSync(
				fileURLToPath(new URL(controllerHookUrl, import.meta.url)),
				'utf8',
			);
			expect(source, controllerHookUrl).not.toContain('@pierre/');
			expect(source, controllerHookUrl).not.toContain('CodeViewHandle');
			expect(source, controllerHookUrl).not.toContain('useFileTree');
		}
	});

	test('keeps file viewer controller hooks independent from visual adapter modules', () => {
		const controllerHookUrls = [
			'./use-bridge-file-viewer-content-controller.ts',
			'./use-bridge-file-viewer-descriptor-request-controller.ts',
			'./use-bridge-file-viewer-frame-intake-controller.ts',
			'./use-bridge-file-viewer-recently-updated-demand.ts',
			'./use-bridge-file-viewer-visible-demand-controller.ts',
			'./use-bridge-file-viewer-shell-model.ts',
			'./use-bridge-file-viewer-store-bindings.ts',
		];

		for (const controllerHookUrl of controllerHookUrls) {
			const source = readFileSync(
				fileURLToPath(new URL(controllerHookUrl, import.meta.url)),
				'utf8',
			);
			expect(source, controllerHookUrl).not.toContain('bridge-file-viewer-tree-panel');
			expect(source, controllerHookUrl).not.toContain('bridge-file-viewer-code-panel');
			expect(source, controllerHookUrl).not.toContain('bridge-file-viewer-pierre-visible-demand');
		}
	});

	test('keeps the file viewer shell as a composition-only surface', () => {
		const shellSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-shell.tsx', import.meta.url)),
			'utf8',
		);

		expect(shellSource).toContain('BridgeFileViewerCodePanel');
		expect(shellSource).toContain('BridgeFileViewerTreePanel');
		expect(shellSource).not.toContain('@pierre/');
		expect(shellSource).not.toContain('useFileTree');
		expect(shellSource).not.toContain('<CodeView');
	});

	test('keeps the file viewer store out of bodies, workers, and viewport geometry', () => {
		const storeSource = readFileSync(
			fileURLToPath(new URL('./state/bridge-file-viewer-store.ts', import.meta.url)),
			'utf8',
		);

		expect(storeSource).toContain('rootSnapshot');
		expect(storeSource).not.toContain('openFileBody');
		expect(storeSource).not.toContain('provisionalOpenFileBody');
		expect(storeSource).not.toContain('scrollTop');
		expect(storeSource).not.toContain('visibleItemIds');
		expect(storeSource).not.toContain('CodeViewHandle');
		expect(storeSource).not.toContain('Worker');
		expect(storeSource).not.toContain('AbortController');
	});

	test('keeps Pierre imports out of app, controller, shell, and store surfaces', () => {
		const fileViewerSources = readFileViewerSourceFiles();
		const pierreImportOwners = fileViewerSources.filter((entry): boolean =>
			entry.source.includes('@pierre/'),
		);
		const forbiddenPierreOwners = pierreImportOwners
			.map((entry) => entry.relativePath)
			.filter(
				(relativePath): boolean =>
					relativePath === 'bridge-file-viewer-app.tsx' ||
					relativePath === 'bridge-file-viewer-shell.tsx' ||
					relativePath.startsWith('state/') ||
					relativePath.startsWith('use-bridge-file-viewer-'),
			);
		const internalPierreImportOwners = pierreImportOwners
			.filter((entry): boolean => /@pierre\/[^'"]+\/(?:src|dist)\//u.test(entry.source))
			.map((entry) => entry.relativePath);

		expect(forbiddenPierreOwners).toEqual([]);
		expect(internalPierreImportOwners).toEqual([]);
	});

	test('keeps Pierre tree viewport DOM reads isolated to the visible-demand adapter', () => {
		const fileViewerSources = readFileViewerSourceFiles();
		const pierreViewportDomOwners = fileViewerSources
			.filter(
				(entry): boolean => entry.relativePath !== 'bridge-file-viewer-pierre-visible-demand.ts',
			)
			.filter((entry): boolean =>
				[
					'getFileTreeContainer',
					'data-file-tree-virtualized-scroll',
					'[data-type="item"][data-item-type="file"][data-item-path]',
				].some((needle): boolean => entry.source.includes(needle)),
			)
			.map((entry): string => entry.relativePath);

		expect(pierreViewportDomOwners).toEqual([]);
	});

	test('keeps the Pierre visible-demand adapter owned by the tree runtime hook', () => {
		const fileViewerSources = readFileViewerSourceFiles();
		const visibleDemandAdapterImporters = fileViewerSources
			.filter(
				(entry): boolean => entry.relativePath !== 'bridge-file-viewer-pierre-visible-demand.ts',
			)
			.filter((entry): boolean => entry.source.includes('bridge-file-viewer-pierre-visible-demand'))
			.map((entry): string => entry.relativePath);

		expect(visibleDemandAdapterImporters).toEqual(['bridge-file-viewer-pierre-tree-runtime.ts']);
	});

	test('keeps the File tree wrapper from owning overflow scrolling', () => {
		const treePanelSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-tree-panel.tsx', import.meta.url)),
			'utf8',
		);

		expect(treePanelSource).toContain('overflow-hidden');
		expect(treePanelSource).not.toContain('overflow-auto');
		expect(treePanelSource).not.toContain('bridge-scrollbar');
	});

	test('keeps File rail shell composition in the neutral right-rail wrapper', () => {
		const treePanelSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-tree-panel.tsx', import.meta.url)),
			'utf8',
		);

		expect(treePanelSource).toContain('BridgeViewerRightRailShell');
		expect(treePanelSource).toContain("bodyTestId: 'bridge-file-viewer-pierre-file-tree'");
		expect(treePanelSource).toContain('rootDataAttributes:');
		expect(treePanelSource).toContain("'data-pierre-file-tree-owner': 'FileTree'");
		expect(treePanelSource).toContain('bodyDataAttributes:');
		expect(treePanelSource).toContain("'data-worktree-tree-total-size':");
		expect(treePanelSource).toContain("'data-worktree-tree-total-size-source':");
		expect(treePanelSource).toContain('toolbarBelow:');
		expect(treePanelSource).not.toContain('<aside');
		expect(treePanelSource).not.toContain('border-l border-[var(--bridge-border-subtle)]');
	});

	test('keeps Pierre visible-demand publishing on ref-backed descriptor lookup', () => {
		const treeRuntimeSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-pierre-tree-runtime.ts', import.meta.url)),
			'utf8',
		);

		expect(treeRuntimeSource).toContain('fileDescriptorByPathRef.current');
		expect(treeRuntimeSource).not.toContain(
			'const fileDescriptorByPath = props.fileDescriptorByPath;',
		);
		expect(treeRuntimeSource).not.toContain('fileDescriptorByPath,\\n\\t\\tmodel,');
	});

	test('keeps File View free of app-side Pierre scroll anchor workarounds', () => {
		const adapterSource = readFileSync(
			fileURLToPath(new URL('../app/bridge-pierre-tree-adapter.ts', import.meta.url)),
			'utf8',
		);
		const treeRuntimeSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-pierre-tree-runtime.ts', import.meta.url)),
			'utf8',
		);

		expect(adapterSource).not.toContain('captureFirstVisiblePierreTreeRowAnchor');
		expect(adapterSource).not.toContain('restorePierreTreeRowAnchor');
		expect(adapterSource).not.toContain('scrollTop +=');
		expect(adapterSource).not.toContain("dispatchEvent(new Event('scroll'");
		expect(treeRuntimeSource).not.toContain('captureFirstVisiblePierreTreeRowAnchor');
		expect(treeRuntimeSource).not.toContain('restorePierreTreeRowAnchor');
		expect(treeRuntimeSource).not.toContain('anchor_workaround');
	});

	test('keeps Pierre tree runtime effects owned by the tree runtime hook', () => {
		const fileViewerSources = readFileViewerSourceFiles();
		const runtimeOwners = treeRuntimeOwnershipNeedles.flatMap((needle): readonly string[] =>
			fileViewerSources
				.filter((entry): boolean => entry.source.includes(needle))
				.map((entry): string => `${needle}: ${entry.relativePath}`),
		);
		const treePanelSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-tree-panel.tsx', import.meta.url)),
			'utf8',
		);

		expect(runtimeOwners).toEqual(
			treeRuntimeOwnershipNeedles.map(
				(needle): string => `${needle}: bridge-file-viewer-pierre-tree-runtime.ts`,
			),
		);
		expect(treePanelSource).not.toContain('requestAnimationFrame');
	});

	test('keeps File CodeView item shaping out of the visual panel', () => {
		const codePanelSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-code-panel.tsx', import.meta.url)),
			'utf8',
		);
		const codeViewItemOwners = readFileViewerSourceFiles()
			.filter((entry): boolean =>
				fileCodeViewItemOwnershipNeedles.some((needle): boolean => entry.source.includes(needle)),
			)
			.map((entry): string => entry.relativePath);

		expect(codePanelSource).toContain('bridgeFileViewerCodeViewItemsForPanelState');
		expect(codePanelSource).not.toContain('contentBodyReservedForSelectedFileExtent');
		expect(codePanelSource).not.toContain('textPaddedToMinimumRenderedLineCount');
		expect(codePanelSource).not.toContain('renderedLineCountForPierreFileContent');
		expect(codeViewItemOwners).toEqual(['bridge-file-viewer-code-view-items.ts']);
	});

	test('keeps selected File CodeView display behind a selected item seam', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const shellModelSource = readFileSync(
			fileURLToPath(new URL('./use-bridge-file-viewer-shell-model.ts', import.meta.url)),
			'utf8',
		);
		const shellSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-shell.tsx', import.meta.url)),
			'utf8',
		);
		const codePanelSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-code-panel.tsx', import.meta.url)),
			'utf8',
		);
		const codeViewItemsSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-code-view-items.ts', import.meta.url)),
			'utf8',
		);

		expect(shellModelSource).not.toContain('selectedCodeViewItem');
		expect(shellSource).toContain('selectedCodeViewItem');
		expect(codePanelSource).toContain('selectedCodeViewItem');
		expect(codeViewItemsSource).toContain('bridgeFileViewerSelectedCodeViewItemForPanelState');
		expect(appSource).toContain(
			'selectedCodeViewItem={renderSnapshotController.selectedCodeViewItem}',
		);
		expect(appSource).not.toContain('renderedOpenFileContent={shellModel.renderedOpenFileContent}');
		expect(shellSource).not.toContain('renderedOpenFileContent');
		expect(codePanelSource).not.toContain('renderedFileContent');
	});

	test('keeps selected File CodeView display behind the shared render snapshot store', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const shellModelSource = readFileSync(
			fileURLToPath(new URL('./use-bridge-file-viewer-shell-model.ts', import.meta.url)),
			'utf8',
		);
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerRenderSnapshotController');
		expect(appSource).toContain(
			'selectedCodeViewItem={renderSnapshotController.selectedCodeViewItem}',
		);
		expect(renderSnapshotControllerSource).toContain('createBridgeMainRenderSnapshotStore');
		expect(renderSnapshotControllerSource).toContain('useSyncExternalStore');
		expect(shellModelSource).not.toContain('renderedOpenFileContentForState');
		expect(shellModelSource).not.toContain('bridgeFileViewerSelectedCodeViewItemForPanelState');
		expect(shellModelSource).not.toContain('openFileBodyState');
		expect(shellModelSource).not.toContain('provisionalOpenFileBody');
		expect(shellModelSource).not.toContain('lastGoodOpenFileContent');
	});

	test('keeps File View terminal states from synthesizing worker availability', () => {
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
			'utf8',
		);

		expect(renderSnapshotControllerSource).toContain('publishOpenFileTerminalState');
		expect(renderSnapshotControllerSource).not.toContain('payload: { state: terminalState.state }');
	});

	test('keeps BridgeWeb TypeScript and TSX files under one thousand lines', () => {
		const bridgeWebSources = readBridgeWebSourceFiles();
		const oversizedSources = bridgeWebSources
			.map((entry) => ({
				lineCount: countSourceLines(entry.source),
				relativePath: entry.relativePath,
			}))
			.filter((entry): boolean => entry.lineCount >= 1000)
			.map((entry): string => `${entry.relativePath}: ${entry.lineCount}`);

		expect(oversizedSources).toEqual([]);
	});
});

interface SourceFileEntry {
	readonly relativePath: string;
	readonly source: string;
}

function readFileViewerSourceFiles(): readonly SourceFileEntry[] {
	const fileViewerDirectory = fileURLToPath(new URL('.', import.meta.url));
	return readSourceFilesInDirectory({
		absoluteDirectory: fileViewerDirectory,
		includeTestFiles: false,
		relativeDirectory: '',
	});
}

function readBridgeWebSourceFiles(): readonly SourceFileEntry[] {
	const bridgeWebSourceDirectory = fileURLToPath(new URL('../../', import.meta.url));
	return readSourceFilesInDirectory({
		absoluteDirectory: bridgeWebSourceDirectory,
		includeTestFiles: true,
		relativeDirectory: '',
	});
}

function readSourceFilesInDirectory(props: {
	readonly absoluteDirectory: string;
	readonly includeTestFiles: boolean;
	readonly relativeDirectory: string;
}): readonly SourceFileEntry[] {
	const entries: SourceFileEntry[] = [];
	for (const directoryEntry of readdirSync(props.absoluteDirectory, { withFileTypes: true })) {
		const relativePath =
			props.relativeDirectory.length === 0
				? directoryEntry.name
				: `${props.relativeDirectory}/${directoryEntry.name}`;
		const absolutePath = join(props.absoluteDirectory, directoryEntry.name);
		if (directoryEntry.isDirectory()) {
			if (excludedSourceDirectoryNames.has(directoryEntry.name)) {
				continue;
			}
			entries.push(
				...readSourceFilesInDirectory({
					absoluteDirectory: absolutePath,
					includeTestFiles: props.includeTestFiles,
					relativeDirectory: relativePath,
				}),
			);
			continue;
		}
		if (
			!(directoryEntry.name.endsWith('.ts') || directoryEntry.name.endsWith('.tsx')) ||
			(!props.includeTestFiles &&
				(directoryEntry.name.includes('.test.') || directoryEntry.name.includes('.browser.')))
		) {
			continue;
		}
		entries.push({
			relativePath,
			source: readFileSync(absolutePath, 'utf8'),
		});
	}
	return entries;
}

const excludedSourceDirectoryNames = new Set([
	'.turbo',
	'.vite',
	'.vitest',
	'coverage',
	'dist',
	'node_modules',
	'playwright-report',
	'test-results',
]);

const treeRuntimeOwnershipNeedles = [
	'prepareFileTreeInput',
	'useFileTree({',
	'bridgeViewerTreeUnsafeCSS',
	'bridge-file-viewer-pierre-visible-demand',
	'recordBridgeTreeScrollVisibleDemandTelemetrySample',
	'model.resetPaths',
	'model.batch',
	'model.subscribe',
	'model.scrollToPath',
] as const;

const fileCodeViewItemOwnershipNeedles = [
	'codeViewPlaceholderItemsForOpenFileState',
	'contentBodyReservedForSelectedFileExtent',
	'textPaddedToMinimumRenderedLineCount',
	'renderedLineCountForPierreFileContent',
] as const;

function countSourceLines(source: string): number {
	if (source.length === 0) {
		return 0;
	}
	const lineCount = source.split('\n').length;
	return source.endsWith('\n') ? lineCount - 1 : lineCount;
}
