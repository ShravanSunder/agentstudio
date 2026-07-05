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
		isBinary: false,
	};
}
