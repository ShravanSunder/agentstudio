import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import { assertSelectedContentRouteProof } from './content-state.js';
import { mapBridgeTelemetrySampleToProof } from './route-probes.ts';
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

	test('retains worker queue correlation attributes from dev telemetry', () => {
		const proof = mapBridgeTelemetrySampleToProof({
			booleanAttributes: {},
			durationMilliseconds: 1,
			name: 'performance.bridge.worker.task',
			numericAttributes: { 'agentstudio.bridge.worker.queue_wait_ms': 9 },
			scope: 'web',
			stringAttributes: {
				'agentstudio.bridge.phase': 'worker_task',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'worker_task',
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.worker.command': 'select',
				'agentstudio.bridge.worker.lane': 'selected',
				'agentstudio.bridge.worker.task_kind': 'message_handler',
			},
			traceContext: null,
		});

		expect(proof.workerCommand).toBe('select');
		expect(proof.workerLane).toBe('selected');
		expect(proof.workerTaskKind).toBe('message_handler');
		expect(proof.numericAttributes['agentstudio.bridge.worker.queue_wait_ms']).toBe(9);
	});
});
