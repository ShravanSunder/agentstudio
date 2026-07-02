import { describe, expect, test } from 'vitest';

import { makeBridgeContentHandle } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import {
	canonicalContentResourceKey,
	contentAddressedResourceKey,
	createBridgeReviewContentRegistry,
} from './review-content-registry.js';

const releaseDeferredNoop = (): void => {};

describe('review content registry', () => {
	test('loads content once per canonical resource key', async () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');
		const requestedUrls: string[] = [];

		const first = await registry.load({
			handle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('loaded once');
			},
		});
		const second = await registry.load({
			handle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('loaded twice');
			},
		});

		expect(first.readText()).toBe('loaded once');
		expect(second.readText()).toBe('loaded once');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
		expect(registry.snapshot()).toMatchObject({
			cachedResourceCount: 1,
			inFlightRequestCount: 0,
		});
	});

	test('evicts the least recently used cached body when max entries is exceeded', async () => {
		const registry = createBridgeReviewContentRegistry({ maxEntries: 1 });
		const firstHandle = makeBridgeContentHandle('item-source', 'head');
		const secondHandle = makeBridgeContentHandle('item-renamed', 'head');
		const requestedUrls: string[] = [];

		await registry.load({
			handle: firstHandle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('first body');
			},
		});
		await registry.load({
			handle: secondHandle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('second body');
			},
		});
		const reloadedFirst = await registry.load({
			handle: firstHandle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('first body reloaded');
			},
		});

		expect(reloadedFirst.readText()).toBe('first body reloaded');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
			'agentstudio://resource/review/content/handle-item-renamed-head?generation=1',
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
		expect(registry.snapshot()).toMatchObject({
			cachedResourceCount: 1,
			inFlightRequestCount: 0,
		});
	});

	test('coalesces concurrent requests for the same content resource', async () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');
		let fetchCount = 0;
		let releaseFetch = releaseDeferredNoop;
		const releasePromise = new Promise<void>((resolve): void => {
			releaseFetch = resolve;
		});

		const first = registry.load({
			handle,
			fetchContent: async (): Promise<Response> => {
				fetchCount += 1;
				await releasePromise;
				return new Response('shared response');
			},
		});
		const second = registry.load({
			handle,
			fetchContent: async (): Promise<Response> => {
				fetchCount += 1;
				return new Response('duplicate response');
			},
		});
		expect(registry.snapshot().inFlightRequestCount).toBe(1);

		releaseFetch();

		const [firstResult, secondResult] = await Promise.all([first, second]);
		expect(firstResult).toMatchObject({ authoritative: true, byteLength: 15, handle });
		expect(secondResult).toMatchObject({ authoritative: true, byteLength: 15, handle });
		expect(firstResult.readText()).toBe('shared response');
		expect(secondResult.readText()).toBe('shared response');
		expect(fetchCount).toBe(1);
	});

	test('keeps shared in-flight content alive when the first viewport consumer aborts', async () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');
		const viewportAbortController = new AbortController();
		let fetchCount = 0;
		let fetchSignal: RequestInit['signal'];
		let releaseFetch = releaseDeferredNoop;
		const releasePromise = new Promise<void>((resolve): void => {
			releaseFetch = resolve;
		});

		const viewportRequest = registry.load({
			handle,
			signal: viewportAbortController.signal,
			fetchContent: async (_url: string, init?: RequestInit): Promise<Response> => {
				fetchCount += 1;
				fetchSignal = init?.signal;
				await releasePromise;
				return new Response('selected body survives viewport churn');
			},
		});
		const selectedRequest = registry.load({
			handle,
			fetchContent: async (): Promise<Response> => {
				fetchCount += 1;
				return new Response('duplicate selected response');
			},
		});
		expect(registry.snapshot().inFlightRequestCount).toBe(1);

		viewportAbortController.abort();
		releaseFetch();

		const [viewportResult, selectedResult] = await Promise.all([viewportRequest, selectedRequest]);
		expect(viewportResult).toMatchObject({ authoritative: true, byteLength: 37, handle });
		expect(selectedResult).toMatchObject({ authoritative: true, byteLength: 37, handle });
		expect(viewportResult.readText()).toBe('selected body survives viewport churn');
		expect(selectedResult.readText()).toBe('selected body survives viewport churn');
		expect(fetchCount).toBe(1);
		expect(fetchSignal).toBeUndefined();
	});

	test('does not cache stale in-flight content after active identity changes', async () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');
		let releaseFetch = releaseDeferredNoop;
		const releasePromise = new Promise<void>((resolve): void => {
			releaseFetch = resolve;
		});

		registry.setActiveIdentity({
			packageId: 'package-one',
			reviewGeneration: 1,
			revision: 0,
		});
		const staleRequest = registry.load({
			handle,
			fetchContent: async (): Promise<Response> => {
				await releasePromise;
				return new Response('stale response');
			},
		});
		expect(registry.snapshot().inFlightRequestCount).toBe(1);

		registry.setActiveIdentity({
			packageId: 'package-two',
			reviewGeneration: 1,
			revision: 0,
		});
		releaseFetch();
		await expect(staleRequest).rejects.toThrow(
			'Bridge content registry discarded stale in-flight content',
		);

		const fresh = await registry.load({
			handle,
			fetchContent: async (): Promise<Response> => new Response('fresh response'),
		});

		expect(fresh.readText()).toBe('fresh response');
		expect(registry.snapshot()).toMatchObject({
			cachedResourceCount: 1,
			inFlightRequestCount: 0,
		});
	});

	test('clears cached bodies when active package identity changes', async () => {
		const registry = createBridgeReviewContentRegistry();
		const firstHandle = makeBridgeContentHandle('item-source', 'head');
		const secondHandle: BridgeContentHandle = {
			...firstHandle,
			reviewGeneration: 2,
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=2&revision=1',
		};
		const requestedUrls: string[] = [];

		registry.setActiveIdentity({
			packageId: 'package-one',
			reviewGeneration: 1,
			revision: 0,
		});
		await registry.load({
			handle: firstHandle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('first generation');
			},
		});
		registry.setActiveIdentity({
			packageId: 'package-one',
			reviewGeneration: 2,
			revision: 1,
		});
		await registry.load({
			handle: secondHandle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('second generation');
			},
		});

		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
			'agentstudio://resource/review/content/handle-item-source-head?generation=2&revision=1',
		]);
		expect(registry.snapshot().cachedResourceCount).toBe(1);
	});

	test('rejects stale handles against the active package identity before fetch', async () => {
		const registry = createBridgeReviewContentRegistry();
		const staleHandle = makeBridgeContentHandle('item-source', 'head');
		const requestedUrls: string[] = [];
		registry.setActiveIdentity({
			packageId: 'package-one',
			reviewGeneration: 2,
			revision: 0,
		});

		await expect(
			registry.load({
				handle: staleHandle,
				fetchContent: async (url: string): Promise<Response> => {
					requestedUrls.push(url);
					return new Response('stale');
				},
			}),
		).rejects.toThrow('Bridge content registry rejected stale content identity');
		expect(requestedUrls).toEqual([]);
	});

	test('preserves descriptor bounds and integrity through shared content loads', async () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');

		await expect(
			registry.load({
				handle,
				maxBytes: 5,
				fetchContent: async (): Promise<Response> => chunkedTextResponse(['abcd', 'ef']),
			}),
		).rejects.toThrow('Bridge text resource stream exceeded issued max bytes');

		await expect(
			registry.load({
				handle,
				integrity: {
					kind: 'wholeHash',
					algorithm: 'sha256',
					value: 'sha256:3173778af72bee80065ddb3dc0fa2319fcaca233bdfd4591d1b3a4ca5115d5a9',
				},
				fetchContent: async (): Promise<Response> => chunkedTextResponse(['tampered ', 'bridge']),
			}),
		).rejects.toThrow('Bridge text resource stream failed whole-body integrity validation');
	});

	test('does not cache preview-only content as stable content', async () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');
		const requestedUrls: string[] = [];

		const first = await registry.load({
			handle,
			integrity: { kind: 'previewOnly' },
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return chunkedTextResponse(['preview ', 'body']);
			},
		});
		const second = await registry.load({
			handle,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return chunkedTextResponse(['authoritative ', 'body']);
			},
		});

		expect(first).toMatchObject({
			authoritative: false,
			byteLength: 12,
			handle,
		});
		expect(second).toMatchObject({
			authoritative: true,
			byteLength: 18,
			handle,
		});
		expect(first.readText()).toBe('preview body');
		expect(second.readText()).toBe('authoritative body');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
	});

	test('canonicalizes resource keys through the shared parser', () => {
		const handle: BridgeContentHandle = {
			...makeBridgeContentHandle('item-source', 'head'),
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?revision=4&generation=1',
		};

		expect(canonicalContentResourceKey(handle)).toBe(
			'agentstudio://resource/review/content/handle-item-source-head?generation=1&revision=4',
		);
	});

	test('peekResource misses before storeResource and hits after', () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');

		expect(registry.peekResource(handle)).toBeNull();

		registry.storeResource({ resource: makeStoredResource(handle, 'stored head text') });

		expect(registry.peekResource(handle)?.readText()).toBe('stored head text');
		expect(registry.snapshot()).toMatchObject({
			cachedResourceCount: 1,
			inFlightRequestCount: 0,
		});
	});

	test('storeResource ignores non-authoritative resources', () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');

		registry.storeResource({
			resource: {
				authoritative: false,
				byteLength: 12,
				handle,
				readText: (): string => 'preview only',
			},
		});

		expect(registry.peekResource(handle)).toBeNull();
	});

	test('storeResource and peekResource treat generation mismatch as a miss, not an error', () => {
		const registry = createBridgeReviewContentRegistry();
		const handle = makeBridgeContentHandle('item-source', 'head');
		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 2, revision: 0 });

		registry.storeResource({ resource: makeStoredResource(handle, 'stale generation text') });

		expect(registry.peekResource(handle)).toBeNull();
		expect(registry.snapshot()).toMatchObject({ cachedResourceCount: 0 });
	});

	test('retains cached content across revision bumps when the content hash is unchanged', () => {
		const registry = createBridgeReviewContentRegistry();
		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 1, revision: 1 });
		const handle = makeBridgeContentHandle('item-source', 'head');
		registry.storeResource({ resource: makeStoredResource(handle, 'unchanged body') });

		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 1, revision: 2 });
		const newRevisionHandle = {
			...handle,
			resourceUrl:
				'agentstudio://resource/review/content/handle-item-source-head?generation=1&revision=2',
		};

		const cachedResource = registry.peekResource(newRevisionHandle);
		expect(cachedResource?.readText()).toBe('unchanged body');
		expect(cachedResource?.handle).toBe(newRevisionHandle);
	});

	test('a changed content hash at a new revision is a miss', () => {
		const registry = createBridgeReviewContentRegistry();
		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 1, revision: 1 });
		const handle = makeBridgeContentHandle('item-source', 'head');
		registry.storeResource({ resource: makeStoredResource(handle, 'old body') });

		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 1, revision: 2 });
		const changedHandle = { ...handle, contentHash: 'sha256:item-source:head:changed' };

		expect(registry.peekResource(changedHandle)).toBeNull();
	});

	test('clears cached content when the generation or package changes', () => {
		const registry = createBridgeReviewContentRegistry();
		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 1, revision: 1 });
		const handle = makeBridgeContentHandle('item-source', 'head');
		registry.storeResource({ resource: makeStoredResource(handle, 'generation one body') });

		registry.setActiveIdentity({ packageId: 'pkg', reviewGeneration: 2, revision: 1 });

		expect(registry.snapshot()).toMatchObject({ cachedResourceCount: 0 });
	});

	test('never caches sentinel content hashes', () => {
		const registry = createBridgeReviewContentRegistry();
		for (const sentinelHash of ['unknown', 'missing-base', 'none...abc123', '']) {
			const handle = {
				...makeBridgeContentHandle('item-source', 'head'),
				contentHash: sentinelHash,
			};
			registry.storeResource({ resource: makeStoredResource(handle, 'uncacheable body') });
			expect(registry.peekResource(handle)).toBeNull();
		}
		expect(registry.snapshot()).toMatchObject({ cachedResourceCount: 0 });
	});

	test('peekResource refreshes LRU order so hot entries survive eviction', () => {
		const registry = createBridgeReviewContentRegistry({ maxEntries: 2 });
		const firstHandle = makeBridgeContentHandle('item-first', 'head');
		const secondHandle = makeBridgeContentHandle('item-second', 'head');
		const thirdHandle = makeBridgeContentHandle('item-third', 'head');

		registry.storeResource({ resource: makeStoredResource(firstHandle, 'first') });
		registry.storeResource({ resource: makeStoredResource(secondHandle, 'second') });
		expect(registry.peekResource(firstHandle)?.readText()).toBe('first');
		registry.storeResource({ resource: makeStoredResource(thirdHandle, 'third') });

		expect(registry.peekResource(secondHandle)).toBeNull();
		expect(registry.peekResource(firstHandle)?.readText()).toBe('first');
		expect(registry.peekResource(thirdHandle)?.readText()).toBe('third');
	});

	test('evictResourceKeys removes exact entries and leaves others cached', () => {
		const registry = createBridgeReviewContentRegistry();
		const firstHandle = makeBridgeContentHandle('item-first', 'head');
		const secondHandle = makeBridgeContentHandle('item-second', 'head');
		registry.storeResource({ resource: makeStoredResource(firstHandle, 'first') });
		registry.storeResource({ resource: makeStoredResource(secondHandle, 'second') });

		const evictedCount = registry.evictResourceKeys([
			requireContentAddressedResourceKey(firstHandle),
		]);

		expect(evictedCount).toBe(1);
		expect(registry.peekResource(firstHandle)).toBeNull();
		expect(registry.peekResource(secondHandle)?.readText()).toBe('second');
	});
});

function requireContentAddressedResourceKey(handle: BridgeContentHandle): string {
	const resourceKey = contentAddressedResourceKey(handle);
	if (resourceKey === null) {
		throw new Error('expected a cacheable content hash in fixture');
	}
	return resourceKey;
}

function makeStoredResource(
	handle: BridgeContentHandle,
	text: string,
): {
	readonly authoritative: boolean;
	readonly byteLength: number;
	readonly handle: BridgeContentHandle;
	readonly readText: () => string;
} {
	return {
		authoritative: true,
		byteLength: text.length,
		handle,
		readText: (): string => text,
	};
}

function chunkedTextResponse(chunks: readonly string[]): Response {
	const encoder = new TextEncoder();
	const body = new ReadableStream<Uint8Array>({
		start(controller): void {
			for (const chunk of chunks) {
				controller.enqueue(encoder.encode(chunk));
			}
			controller.close();
		},
	});
	return Object.assign(new Response(body), {
		text: async (): Promise<string> => {
			throw new Error('whole body text() should not be used for Bridge content resources');
		},
	});
}
