import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge file viewer source structure', () => {
	test('compile-deletes the legacy File product carrier and React lifecycle owners', () => {
		const appDirectory = fileURLToPath(new URL('../app/', import.meta.url));
		const fileViewerDirectory = fileURLToPath(new URL('./', import.meta.url));
		const productionSources = [
			...readSourceFilesInDirectory({
				absoluteDirectory: appDirectory,
				includeTestFiles: false,
				relativeDirectory: 'app',
			}),
			...readSourceFilesInDirectory({
				absoluteDirectory: fileViewerDirectory,
				includeTestFiles: false,
				relativeDirectory: 'file-viewer',
			}),
		];
		const forbiddenOwners = [
			'bridge-file-viewer-frame-controller',
			'bridge-file-viewer-worktree-file-surface-transport',
			'createBridgeAppNativeWorktreeFileBackend',
			'useBridgeFileViewerContentController',
			'useBridgeFileViewerDescriptorRequestController',
			'useBridgeFileViewerFrameIntakeController',
			'useBridgeFileViewerInitialSurfaceLoader',
			'useBridgeFileViewerRecentlyUpdatedDemand',
			'useBridgeFileViewerSelectionEffects',
			'worktreeFileSurfaceTransport',
		].flatMap((token): readonly string[] =>
			productionSources
				.filter((entry): boolean => entry.source.includes(token))
				.map((entry): string => `${token}: ${entry.relativePath}`),
		);

		expect(forbiddenOwners).toEqual([]);
	});

	test('hard-cuts mounted File View from legacy frame and descriptor-request authority', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const forbiddenMountedAuthority = [
			'createBridgeFileViewerFrameApplier',
			'useBridgeFileViewerContentController',
			'useBridgeFileViewerDescriptorRequestController',
			'useBridgeFileViewerFrameIntakeController',
			'useBridgeFileViewerRecentlyUpdatedDemand',
			'useBridgeFileViewerSelectionEffects',
			'WorktreeFileProtocolFrame',
			'WorktreeFileRuntimeFrameApplier',
			'worktreeFileSurfaceTransport?.',
			'requestFileDescriptor',
			'runtime.openFile',
			'result.content.readText',
		].filter((token): boolean => appSource.includes(token));

		expect(forbiddenMountedAuthority).toEqual([]);
		expect(appSource).toContain('renderSnapshotController.fileDisplaySnapshot');
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
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
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
		expect(renderSnapshotControllerSource).not.toContain('renderSnapshotStore.setLocalViewport');
	});

	test('keeps the pane-owned File surface client instance scoped', () => {
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
			'utf8',
		);
		const browserHarnessAppSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-browser-test-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(renderSnapshotControllerSource).toContain('BridgeFileViewerSurfaceClientProvider');
		expect(renderSnapshotControllerSource).toContain('BridgePaneSurfaceClient');
		expect(renderSnapshotControllerSource).not.toContain(
			'bridgeFileViewerRuntimeTransportFactoryForTest',
		);
		expect(renderSnapshotControllerSource).not.toContain(
			'setBridgeFileViewerRuntimeTransportFactoryForTest',
		);
		expect(browserHarnessAppSource).toContain('BridgeFileViewerSurfaceClientProvider');
		expect(browserHarnessAppSource).not.toContain(
			'setBridgeFileViewerRuntimeTransportFactoryForTest',
		);
	});

	test('keeps frame application out of the file viewer app coordinator', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(appSource).not.toContain('useBridgeFileViewerFrameIntakeController');
		expect(appSource).not.toContain('applyFramesToRuntime');
		expect(appSource).not.toContain('reconcileOpenFileStateWithFrames');
	});

	test('keeps File View free of the legacy fetch-capable runtime', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const legacyRuntimePaths = [
			'./bridge-file-viewer-runtime.ts',
			'./bridge-file-viewer-state.ts',
			'../worktree-file-surface/worktree-file-surface-runtime.ts',
			'../worktree-file-surface/worktree-file-surface-runtime-support.ts',
			'../worktree-file-surface/worktree-file-app.tsx',
		].map((relativePath): string => fileURLToPath(new URL(relativePath, import.meta.url)));

		expect(legacyRuntimePaths.filter(existsSync)).toEqual([]);
		expect(appSource).not.toContain('createBridgeFileViewerRuntime');
		expect(appSource).not.toContain('WorktreeFileSurfaceRuntime');
	});

	test('keeps Pierre runtime imports out of file viewer controller hooks', () => {
		const controllerHookUrls = [
			'./use-bridge-file-viewer-visible-demand-controller.ts',
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
			'./use-bridge-file-viewer-visible-demand-controller.ts',
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

	test('keeps Pierre visible-demand publishing on ref-backed worker display rows', () => {
		const treeRuntimeSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-pierre-tree-runtime.ts', import.meta.url)),
			'utf8',
		);

		expect(treeRuntimeSource).toContain('treeRowByPathRef.current.get');
		expect(treeRuntimeSource).not.toContain('new Map(props.treeRows.map');
		expect(treeRuntimeSource).not.toContain('.find(');
		expect(treeRuntimeSource).not.toContain('fileDescriptorByPath');
		expect(treeRuntimeSource).not.toContain('descriptorRefs');
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

	test('keeps mounted File query projection in the comm worker', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);
		const displayModelSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-display-model.ts', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('dispatchFileViewQueryFact');
		expect(appSource).not.toContain('descriptorProjection');
		expect(appSource).not.toMatch(/bridgeFileViewerDisplayModelForSnapshot\([^)]*,/u);
		expect(displayModelSource).not.toContain('readonly paths: readonly string[]');
		expect(displayModelSource).not.toContain('readonly treeRows:');
		expect(displayModelSource).not.toContain('RegExp');
		expect(displayModelSource).not.toContain('.toSorted(');
		expect(displayModelSource).not.toContain('.filter(');
		expect(displayModelSource).not.toContain('searchMode');
		expect(displayModelSource).not.toContain('filterMode');
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

		expect(shellSource).toContain('selectedCodeViewItem');
		expect(codePanelSource).toContain('selectedCodeViewItem');
		expect(codeViewItemsSource).toContain('bridgeFileViewerCodeViewItemsForPanelState');
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
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerRenderSnapshotController');
		expect(appSource).toContain(
			'selectedCodeViewItem={renderSnapshotController.selectedCodeViewItem}',
		);
		expect(renderSnapshotControllerSource).toContain('fileViewClient.renderStore');
		expect(renderSnapshotControllerSource).toContain('useSyncExternalStore');
		expect(renderSnapshotControllerSource).not.toContain('renderedOpenFileContentForState');
		expect(renderSnapshotControllerSource).not.toContain(
			'bridgeFileViewerSelectedCodeViewItemForPanelState',
		);
		expect(renderSnapshotControllerSource).not.toContain('openFileBodyState');
		expect(renderSnapshotControllerSource).not.toContain('provisionalOpenFileBody');
		expect(renderSnapshotControllerSource).not.toContain('lastGoodOpenFileContent');
	});

	test('keeps File View terminal states from synthesizing worker availability', () => {
		const renderSnapshotControllerSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-render-snapshot-controller.ts', import.meta.url)),
			'utf8',
		);

		expect(renderSnapshotControllerSource).not.toContain('publishOpenFileTerminalState');
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
	'useFileTree({',
	'bridgeViewerTreeUnsafeCSS',
	'bridge-file-viewer-pierre-visible-demand',
	'recordBridgeTreeScrollVisibleDemandTelemetrySample',
	'model.subscribe',
	'model.scrollToPath',
] as const;

const fileCodeViewItemOwnershipNeedles = [
	'bridgeFileViewerPlaceholderItemsForOpenState',
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
