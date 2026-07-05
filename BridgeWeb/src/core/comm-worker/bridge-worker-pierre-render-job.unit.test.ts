import { describe, expect, test } from 'vitest';

import {
	buildBridgeWorkerPierreRenderJob,
	type BuildBridgeWorkerPierreRenderJobProps,
} from './bridge-worker-pierre-render-job.js';

describe('Bridge worker Pierre render job', () => {
	test('encodes bounded Pierre render jobs with rank cache key and clone budget class', () => {
		const textBytes = new ArrayBuffer(64);
		const jobProps = {
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:abc123',
			contentHash: 'abc123',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 40,
				totalLineCount: 400,
			},
			payload: {
				kind: 'textWindow',
				textBytes,
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		} satisfies BuildBridgeWorkerPierreRenderJobProps;
		const job = buildBridgeWorkerPierreRenderJob(jobProps);

		expect(job).toMatchObject({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:abc123',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budgetClass: 'interactive',
			payloadByteLength: 64,
			windowLineCount: 40,
		});
		expect(job.payload.textBytes).toBe(textBytes);

		expect(() =>
			buildBridgeWorkerPierreRenderJob({
				...jobProps,
				budget: {
					className: 'interactive',
					maxBytes: 32,
					maxWindowLines: 400,
				},
			}),
		).toThrow(/exceeds.*byte/i);
	});
});
