import { parseDiffFromFile } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import {
	buildBridgeWorkerPierreRenderJob,
	bridgeWorkerPierreRenderPayloadSchema,
} from './bridge-worker-pierre-render-job.js';

describe('Bridge worker Pierre render job', () => {
	test('rejects raw text window payloads at the render-job boundary', () => {
		expect(
			bridgeWorkerPierreRenderPayloadSchema.safeParse({
				kind: 'textWindow',
				textBytes: new ArrayBuffer(8),
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerPierreRenderPayloadSchema.safeParse({
				kind: 'diffTextWindow',
				baseTextBytes: new ArrayBuffer(8),
				headTextBytes: new ArrayBuffer(8),
			}).success,
		).toBe(false);
	});

	test('encodes worker-prepared CodeView file items without raw text window payloads', () => {
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-worker-file',
			renderKind: 'fileText',
			contentCacheKey: 'pierre-content:sha256:worker-file',
			contentHash: 'sha256:worker-file',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 2,
				totalLineCount: 2,
			},
			payload: {
				kind: 'codeViewFileItem',
				item: {
					id: 'item-worker-file',
					type: 'file',
					file: {
						name: 'Sources/App.ts',
						contents: 'export const answer = 42;\n',
						cacheKey: 'pierre-content:sha256:worker-file',
						lang: 'typescript',
					},
					version: 5,
					bridgeMetadata: {
						itemId: 'item-worker-file',
						displayPath: 'Sources/App.ts',
						contentState: 'hydrated',
						contentRoles: ['head'],
						cacheKey: 'pierre-content:sha256:worker-file',
						lineCount: 1,
					},
				},
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});

		expect(job.payload.kind).toBe('codeViewFileItem');
		expect(job.payloadByteLength).toBeGreaterThan(0);
	});

	test('encodes worker-prepared CodeView diff items with rank cache key and clone budget class', () => {
		const fileDiff = parseDiffFromFile(
			{
				name: 'Sources/App.ts',
				contents: 'export const answer = 41;\n',
				cacheKey: 'pierre-content:sha256:base',
			},
			{
				name: 'Sources/App.ts',
				contents: 'export const answer = 42;\n',
				cacheKey: 'pierre-content:sha256:head',
			},
		);
		const jobProps = {
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			contentHash: 'sha256:base|sha256:head',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 40,
				totalLineCount: 400,
			},
			payload: {
				kind: 'codeViewDiffItem',
				item: {
					id: 'item-1',
					type: 'diff',
					fileDiff,
					version: 2,
					bridgeMetadata: {
						itemId: 'item-1',
						displayPath: 'Sources/App.ts',
						contentState: 'hydrated',
						contentRoles: ['base', 'head'],
						cacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
						lineCount: 2,
					},
				},
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		} satisfies Parameters<typeof buildBridgeWorkerPierreRenderJob>[0];
		const job = buildBridgeWorkerPierreRenderJob(jobProps);

		expect(job).toMatchObject({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budgetClass: 'interactive',
			windowLineCount: 40,
		});
		expect(job.payload.kind).toBe('codeViewDiffItem');
		expect(job.payloadByteLength).toBeGreaterThan(0);

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
					kind: 'codeViewFileItem',
					item: {
						id: 'item-bad-diff',
						type: 'file',
						file: {
							name: 'Sources/App.ts',
							contents: 'export const answer = 42;\n',
							cacheKey: 'pierre-content:sha256:head',
						},
						bridgeMetadata: {
							itemId: 'item-bad-diff',
							displayPath: 'Sources/App.ts',
							contentState: 'hydrated',
							contentRoles: ['head'],
							cacheKey: 'pierre-content:sha256:head',
							lineCount: 1,
						},
					},
				},
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 400,
				},
			}),
		).toThrow(/review diff.*codeViewDiffItem/i);
	});
});
