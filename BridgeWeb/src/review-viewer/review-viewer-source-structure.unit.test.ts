import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Review viewer source structure', () => {
	test('keeps review data controllers outside the lazy visual shell boundary', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const shellBoundarySource = readSource('../app/bridge-app-review-viewer-shell-boundary.tsx');

		expect(modeSource).toContain('useBridgeReviewViewerStore');
		expect(modeSource).toContain('useBridgeReviewControlEventListeners');
		expect(modeSource).toContain('useBridgeReviewIntakeController');
		expect(modeSource).toContain('useBridgeReviewMetadataInterestRuntime');
		expect(modeSource).toContain('useBridgeReviewProjectionCoordinator');
		expect(modeSource).toContain('useVisibleReviewContentHydration');
		expect(modeSource).toContain('useBridgeReviewSelectedContentEffect');
		expect(modeSource).toContain('useSelectedReviewContentDemandController');
		expect(modeSource).toContain('BridgeReviewViewerShellBoundary');
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

	test('keeps selected Review content demand effects in the demand controller module', () => {
		const modeSource = readSource('../app/bridge-app-review-viewer-mode.tsx');
		const selectedContentControllerSource = readSource(
			'../app/bridge-app-review-selected-content-controller.ts',
		);

		expect(modeSource).toContain('useBridgeReviewSelectedContentEffect');
		expect(modeSource).not.toContain('useLayoutEffect((): (() => void)');
		expect(modeSource).not.toContain('return startSelectedReviewContentDemand({');

		expect(selectedContentControllerSource).toContain('useBridgeReviewSelectedContentEffect');
		expect(selectedContentControllerSource).toContain(
			'selectedContentAbortControllerRef.current?.abort()',
		);
		expect(selectedContentControllerSource).not.toContain('BridgeReviewViewerShellBoundary');
		expect(selectedContentControllerSource).not.toContain('@pierre/');
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
	});
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
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
