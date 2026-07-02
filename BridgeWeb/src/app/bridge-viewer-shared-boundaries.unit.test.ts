import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

async function source(path: string): Promise<string> {
	return await readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
}

describe('BridgeViewer shared component boundaries', () => {
	test('FileViewer shell consumes neutral BridgeViewer chrome instead of Review-owned chrome', async () => {
		const fileViewerShell = await source('src/file-viewer/bridge-file-viewer-shell.tsx');

		expect(fileViewerShell).not.toContain('../review-viewer/chrome/');
	});

	test('FileViewer app consumes neutral tree contracts instead of Review-owned tree modules', async () => {
		const fileViewerApp = await source('src/file-viewer/bridge-file-viewer-app.tsx');

		expect(fileViewerApp).not.toContain('../review-viewer/trees/bridge-file-viewer-tree-panel.js');
	});

	test('Pierre tree adapter stays neutral from FileView and Review domain modules', async () => {
		const pierreTreeAdapter = await source('src/app/bridge-pierre-tree-adapter.ts');

		expect(pierreTreeAdapter).not.toContain('../file-viewer/');
		expect(pierreTreeAdapter).not.toContain('../review-viewer/');
		expect(pierreTreeAdapter).not.toContain('../features/worktree-file/');
		expect(pierreTreeAdapter).not.toContain('../features/review/');
		expect(pierreTreeAdapter).not.toContain('@pierre/');
		expect(pierreTreeAdapter).not.toContain('WorktreeFileDescriptor');
		expect(pierreTreeAdapter).not.toContain('canFetchWorktreeFileDescriptorContent');
		expect(pierreTreeAdapter).not.toContain('BridgeReviewPackage');
		expect(pierreTreeAdapter).not.toContain('BridgeReviewProjectionResult');
		expect(pierreTreeAdapter).not.toContain('ReviewTreeRowMetadata');
	});

	test('Pierre tree DOM selectors live in the neutral adapter only', async () => {
		const adapterSource = await source('src/app/bridge-pierre-tree-adapter.ts');
		const treeSelectorNeedles = [
			'data-file-tree-virtualized-scroll',
			'[data-type="item"][data-item-type="file"][data-item-path]',
		];
		const consumerSourcePaths = [
			'src/file-viewer/bridge-file-viewer-pierre-tree-runtime.ts',
			'src/file-viewer/bridge-file-viewer-pierre-visible-demand.ts',
			'src/review-viewer/trees/bridge-trees-controller.ts',
			'src/review-viewer/trees/bridge-trees-panel.tsx',
		];
		const consumerSources = await Promise.all(
			consumerSourcePaths.map(
				async (
					consumerSourcePath,
				): Promise<{
					readonly path: string;
					readonly source: string;
				}> => ({
					path: consumerSourcePath,
					source: await source(consumerSourcePath),
				}),
			),
		);

		for (const selectorNeedle of treeSelectorNeedles) {
			expect(adapterSource, selectorNeedle).toContain(selectorNeedle);
		}
		for (const consumerSource of consumerSources) {
			for (const selectorNeedle of treeSelectorNeedles) {
				expect(consumerSource.source, `${consumerSource.path}: ${selectorNeedle}`).not.toContain(
					selectorNeedle,
				);
			}
		}
	});

	test('shared header tests do not reach through the Review shell for shared primitive proof', async () => {
		const contentHeaderTest = await source('src/app/bridge-viewer-content-header.browser.test.tsx');

		expect(contentHeaderTest).not.toContain('../review-viewer/shell/review-viewer-shell.js');
	});
});
