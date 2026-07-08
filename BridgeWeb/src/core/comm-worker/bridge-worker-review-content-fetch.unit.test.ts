import { describe, expect, test } from 'vitest';

import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { fetchBridgeWorkerReviewContentResource } from './bridge-worker-review-content-fetch.js';

describe('Bridge worker review content fetch', () => {
	test('fetches typed review content descriptors through injected worker fetch', async () => {
		const calls: string[] = [];
		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor: makeContentRequestDescriptor(),
			fetchContent: async (url: string): Promise<Response> => {
				calls.push(url);
				return new Response('hello bridge worker');
			},
		});

		expect(calls).toEqual([
			'agentstudio://resource/review/content/handle-item-1-head?generation=4',
		]);
		expect(result).toMatchObject({
			itemId: 'item-1',
			role: 'head',
			contentHash: 'sha256:item-1:head',
			contentHashAlgorithm: 'fixture-preview',
			language: 'swift',
			byteLength: 19,
		});
		expect(result.textBytes.byteLength).toBe(19);
		expect(new TextDecoder().decode(result.textBytes)).toBe('hello bridge worker');
	});

	test('uses descriptor max bytes instead of display size for inexact review content', async () => {
		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor: {
				...makeContentRequestDescriptor(),
				sizeBytes: 4,
				maxBytes: 64,
			},
			fetchContent: async (): Promise<Response> => new Response('hello bridge worker'),
		});

		expect(result.byteLength).toBe(19);
		expect(result.text).toBe('hello bridge worker');
	});

	test('rejects exact review content when streamed byte length differs from expected bytes', async () => {
		await expect(
			fetchBridgeWorkerReviewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					sizeBytes: 0,
					expectedBytes: 0,
					maxBytes: 1,
				},
				fetchContent: async (): Promise<Response> => new Response('x'),
			}),
		).rejects.toThrow(/expected 0 bytes/i);
	});

	test('rejects stale or mismatched descriptor resource urls before fetch', async () => {
		const fetchCalls: string[] = [];

		await expect(
			fetchBridgeWorkerReviewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					resourceUrl: 'agentstudio://resource/review/content/handle-item-1-head?generation=3',
				},
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return new Response('must not fetch');
				},
			}),
		).rejects.toThrow(/descriptor resource url/i);
		expect(fetchCalls).toEqual([]);
	});

	test('rejects binary descriptors before text fetch', async () => {
		await expect(
			fetchBridgeWorkerReviewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					isBinary: true,
				},
				fetchContent: async (): Promise<Response> => new Response('must not fetch'),
			}),
		).rejects.toThrow(/binary/i);
	});
});

function makeContentRequestDescriptor(): BridgeWorkerReviewContentRequestDescriptor {
	return {
		itemId: 'item-1',
		role: 'head',
		handleId: 'handle-item-1-head',
		reviewGeneration: 4,
		resourceUrl: 'agentstudio://resource/review/content/handle-item-1-head?generation=4',
		contentHash: 'sha256:item-1:head',
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		sizeBytes: 1024,
		maxBytes: 1024,
		isBinary: false,
	};
}
