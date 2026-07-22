import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

const perFeatureWorkerFactoryOwners = [
	{
		relativePath: '../../app/bridge-app-review-render-snapshot-controller.ts',
		token: 'createBridgeReviewCommWorkerTransportDispatcher',
	},
	{
		relativePath: '../../app/bridge-app.tsx',
		token: 'createBridgeReviewRuntimeProtocolDispatcher',
	},
	{
		relativePath: '../../file-viewer/bridge-file-viewer-render-snapshot-controller.ts',
		token: 'createBridgeReviewCommWorkerTransportDispatcher',
	},
] as const;

describe('Bridge pane comm worker production topology', () => {
	test('has one pane-owned worker session', () => {
		const paneSessionSource = readOptionalSource('bridge-pane-comm-worker-session.ts');

		expect(paneSessionSource).toContain('BridgePaneCommWorkerSession');
		expect(paneSessionSource).toMatch(/workerFactory|new Worker/u);
	});

	test('has no per-feature comm-worker factory owners', () => {
		const perFeatureFactoryViolations = perFeatureWorkerFactoryOwners.flatMap(
			(owner): readonly string[] => {
				const source = readSource(owner.relativePath);
				return source.includes(owner.token) ? [`${owner.relativePath}: ${owner.token}`] : [];
			},
		);

		expect(perFeatureFactoryViolations).toEqual([]);
	});
});

function readOptionalSource(relativePath: string): string {
	const sourcePath = fileURLToPath(new URL(relativePath, import.meta.url));
	return existsSync(sourcePath) ? readFileSync(sourcePath, 'utf8') : '';
}

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}
