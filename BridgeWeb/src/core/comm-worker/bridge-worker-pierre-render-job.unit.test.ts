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
			renderKind: 'fileText',
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
			renderKind: 'fileText',
			contentCacheKey: 'pierre-content:sha256:abc123',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budgetClass: 'interactive',
			payloadByteLength: 64,
			windowLineCount: 40,
		});
		expect(job.payload.kind).toBe('textWindow');
		if (job.payload.kind === 'textWindow') {
			expect(job.payload.textBytes).toBe(textBytes);
		}

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

	test('encodes modified review diff jobs with base and head text windows', () => {
		const baseTextBytes = new ArrayBuffer(48);
		const headTextBytes = new ArrayBuffer(80);

		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-diff',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			contentHash: 'sha256:base+head',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 32,
				totalLineCount: 320,
			},
			payload: {
				kind: 'diffTextWindow',
				baseTextBytes,
				headTextBytes,
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});

		expect(job).toMatchObject({
			itemId: 'item-diff',
			renderKind: 'reviewDiff',
			payloadByteLength: 128,
			windowLineCount: 32,
		});
		expect(job.payload.kind).toBe('diffTextWindow');
		if (job.payload.kind === 'diffTextWindow') {
			expect(job.payload.baseTextBytes).toBe(baseTextBytes);
			expect(job.payload.headTextBytes).toBe(headTextBytes);
		}
	});

	test('rejects review diff jobs that try to use a single file text payload', () => {
		expect(() =>
			buildBridgeWorkerPierreRenderJob({
				itemId: 'item-bad-diff',
				renderKind: 'reviewDiff',
				contentCacheKey: 'pierre-content:sha256:head',
				contentHash: 'sha256:head',
				language: 'typescript',
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				window: {
					startLine: 1,
					endLine: 20,
					totalLineCount: 200,
				},
				payload: {
					kind: 'textWindow',
					textBytes: new ArrayBuffer(64),
				},
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 400,
				},
			}),
		).toThrow(/review diff.*diffTextWindow/i);
	});

	test('encodes one-sided review diff jobs with exactly one text window side', () => {
		const headTextBytes = new ArrayBuffer(96);

		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-added',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:empty|pierre-content:sha256:head',
			contentHash: 'sha256:head',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 24,
				totalLineCount: 24,
			},
			payload: {
				kind: 'diffTextWindow',
				baseTextBytes: null,
				headTextBytes,
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});

		expect(job.payloadByteLength).toBe(96);
		expect(job.payload.kind).toBe('diffTextWindow');
		if (job.payload.kind === 'diffTextWindow') {
			expect(job.payload.baseTextBytes).toBeNull();
			expect(job.payload.headTextBytes).toBe(headTextBytes);
		}
	});
});
