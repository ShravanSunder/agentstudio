import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

describe('Bridge Review Vite shell preload', () => {
	test('fetches the lazy Review shell before long-lived product streams open', async () => {
		const devBootstrap = await readFile(
			new URL('../src/app/bridge-app-dev-bootstrap.tsx', import.meta.url),
			'utf8',
		);
		const preloadOffset = devBootstrap.indexOf('await preloadBridgeReviewViewerShell();');
		const productSessionOffset = devBootstrap.indexOf('installBridgeAppDevProductSessionHost({');

		expect(preloadOffset).toBeGreaterThanOrEqual(0);
		expect(preloadOffset).toBeLessThan(productSessionOffset);
		expect(devBootstrap).toContain(
			"await import('../review-viewer/shell/review-viewer-shell.js');",
		);
	});
});
