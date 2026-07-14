import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import { assertSelectedContentRouteProof } from './content-state.js';
import type { WorktreeFileContentRouteProbe } from './types.js';

const routeProbesSourcePath = fileURLToPath(new URL('./route-probes.ts', import.meta.url));

describe('Bridge viewer product File content route probe', () => {
	test('correlates multiplexed product POST hits by typed descriptor identity', () => {
		// Arrange
		const productContentUrl =
			'http://127.0.0.1:5173/__bridge-product/content?scenario=current-worktree';
		const probe: WorktreeFileContentRouteProbe = {
			dispose: async (): Promise<void> => undefined,
			foreignHitCount: (): number => 0,
			foreignHitUrls: (): readonly string[] => [],
			hitCount: (): number => 2,
			hits: () => [
				{
					contentRequestId: 'request-old',
					descriptorId: 'descriptor-old',
					leaseId: 'lease-old',
					url: productContentUrl,
				},
				{
					contentRequestId: 'request-target',
					descriptorId: 'descriptor-target',
					leaseId: 'lease-target',
					url: productContentUrl,
				},
			],
			hitUrls: (): readonly string[] => [productContentUrl, productContentUrl],
		};

		// Act
		const proof = assertSelectedContentRouteProof({
			expectedContentHandle: 'descriptor-target',
			probe,
		});

		// Assert
		expect(proof.selectedResourceUrlContainsHandle).toBe(true);
		expect(proof.selectedResourceUrlUsesDevServerFrontDoor).toBe(true);
	});

	test('contains no legacy File content route matcher', async () => {
		const source = await readFile(routeProbesSourcePath, 'utf8');

		expect(source).toContain('parseBridgeWorktreeDevFileContentRouteRequest');
		expect(source).toContain("'**/__bridge-product/content**'");
		expect(source).not.toContain('/__bridge-worktree/file-content');
		expect(source).not.toContain('MatchesHandle');
	});
});
