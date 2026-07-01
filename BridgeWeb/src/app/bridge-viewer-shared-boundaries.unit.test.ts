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

	test('shared header tests do not reach through the Review shell for shared primitive proof', async () => {
		const contentHeaderTest = await source('src/app/bridge-viewer-content-header.browser.test.tsx');

		expect(contentHeaderTest).not.toContain('../review-viewer/shell/review-viewer-shell.js');
	});
});
