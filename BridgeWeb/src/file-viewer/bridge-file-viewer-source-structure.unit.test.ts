import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge file viewer source structure', () => {
	test('keeps content body loading in the content controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerContentController');
		expect(appSource).not.toContain('runtime.openFile');
		expect(appSource).not.toContain('runtime.refreshOpenFile');
		expect(appSource).not.toContain('recordBridgeViewerFileOpenReadyTelemetrySample');
	});

	test('keeps visible viewport demand dispatch in a controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerVisibleDemandController');
		expect(appSource).not.toContain('recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample');
		expect(appSource).not.toContain('runtime.dispatchDemandStimuli');
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

	test('keeps Pierre runtime imports out of file viewer controller hooks', () => {
		const controllerHookUrls = [
			'./use-bridge-file-viewer-content-controller.ts',
			'./use-bridge-file-viewer-frame-intake-controller.ts',
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
			'./use-bridge-file-viewer-frame-intake-controller.ts',
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

	test('keeps the Pierre visible-demand adapter owned by the tree panel', () => {
		const fileViewerSources = readFileViewerSourceFiles();
		const visibleDemandAdapterImporters = fileViewerSources
			.filter(
				(entry): boolean => entry.relativePath !== 'bridge-file-viewer-pierre-visible-demand.ts',
			)
			.filter((entry): boolean => entry.source.includes('bridge-file-viewer-pierre-visible-demand'))
			.map((entry): string => entry.relativePath);

		expect(visibleDemandAdapterImporters).toEqual(['bridge-file-viewer-tree-panel.tsx']);
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

function countSourceLines(source: string): number {
	if (source.length === 0) {
		return 0;
	}
	const lineCount = source.split('\n').length;
	return source.endsWith('\n') ? lineCount - 1 : lineCount;
}
