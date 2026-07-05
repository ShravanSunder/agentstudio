import { describe, expect, test } from 'vitest';

import type { BridgeWorkerReviewRenderSemantics } from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import { planBridgeWorkerReviewPierreRenderJob } from './bridge-worker-review-pierre-job-planner.js';

describe('Bridge worker review Pierre job planner', () => {
	test('plans modified review diffs from base and head content windows', () => {
		const baseTextBytes = new ArrayBuffer(40);
		const headTextBytes = new ArrayBuffer(64);

		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					lineCount: 120,
					role: 'base',
					textBytes: baseTextBytes,
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					language: 'typescript',
					lineCount: 80,
					role: 'head',
					textBytes: headTextBytes,
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { base: 120, head: 80 },
				itemKind: 'diff',
			}),
		});

		expect(job).toMatchObject({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey:
				'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
			contentHash: 'sha256:item-1:base|sha256:item-1:head',
			language: 'typescript',
			payloadByteLength: 104,
			window: {
				startLine: 1,
				endLine: 50,
				totalLineCount: 120,
			},
			windowLineCount: 50,
		});
		expect(job?.payload.kind).toBe('diffTextWindow');
		if (job?.payload.kind === 'diffTextWindow') {
			expect(job.payload.baseTextBytes).toBe(baseTextBytes);
			expect(job.payload.headTextBytes).toBe(headTextBytes);
		}
	});

	test('does not plan modified review diffs until both sides are fetched', () => {
		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					role: 'base',
					textBytes: new ArrayBuffer(32),
				}),
			],
			semantics: makeRenderSemantics({
				itemKind: 'diff',
			}),
		});

		expect(job).toBeNull();
	});

	test('plans one-sided added review diffs from the head side only', () => {
		const headTextBytes = new ArrayBuffer(72);

		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 100,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					lineCount: 33,
					role: 'head',
					textBytes: headTextBytes,
				}),
			],
			semantics: makeRenderSemantics({
				changeKind: 'added',
				contentLineCountsByRole: { head: 33 },
				itemKind: 'file',
			}),
		});

		expect(job).toMatchObject({
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:empty|pierre-content:fixture-preview:sha256:item-1:head',
			contentHash: 'empty|sha256:item-1:head',
			language: 'swift',
			payloadByteLength: 72,
			windowLineCount: 33,
		});
		expect(job?.payload.kind).toBe('diffTextWindow');
		if (job?.payload.kind === 'diffTextWindow') {
			expect(job.payload.baseTextBytes).toBeNull();
			expect(job.payload.headTextBytes).toBe(headTextBytes);
		}
	});

	test('plans file text jobs from a single preferred resource and language fallback', () => {
		const fileTextBytes = new ArrayBuffer(128);

		const job = planBridgeWorkerReviewPierreRenderJob({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					language: null,
					lineCount: 45,
					role: 'file',
					textBytes: fileTextBytes,
				}),
			],
			semantics: makeRenderSemantics({
				contentLineCountsByRole: { file: 45 },
				itemKind: 'file',
				language: null,
			}),
		});

		expect(job).toMatchObject({
			renderKind: 'fileText',
			contentCacheKey: 'pierre-content:fixture-preview:sha256:item-1:file',
			contentHash: 'sha256:item-1:file',
			language: 'text',
			payloadByteLength: 128,
			windowLineCount: 45,
		});
		expect(job?.payload.kind).toBe('textWindow');
		if (job?.payload.kind === 'textWindow') {
			expect(job.payload.textBytes).toBe(fileTextBytes);
		}
	});
});

function makeRenderSemantics(
	overrides: Partial<BridgeWorkerReviewRenderSemantics> = {},
): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/View.swift',
		basePath: 'Sources/App/View.swift',
		headPath: 'Sources/App/View.swift',
		language: 'swift',
		contentLineCountsByRole: {},
		...overrides,
	};
}

function makeFetchedReviewContentResource(props: {
	readonly contentHash?: string;
	readonly language?: string | null;
	readonly lineCount?: number;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly textBytes: ArrayBuffer;
}): BridgeWorkerFetchedReviewContentResource {
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash ?? `sha256:item-1:${props.role}`,
		contentHashAlgorithm: 'fixture-preview',
		language: props.language === undefined ? 'swift' : props.language,
		byteLength: props.textBytes.byteLength,
		textBytes: props.textBytes,
	};
}
