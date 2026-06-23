import { describe, expect, test } from 'vitest';

import { makeBridgeContentHandle } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import {
	canonicalContentResourceKey,
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

		expect(first.text).toBe('loaded once');
		expect(second.text).toBe('loaded once');
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

		expect(reloadedFirst.text).toBe('first body reloaded');
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

		await expect(Promise.all([first, second])).resolves.toEqual([
			{ handle, text: 'shared response' },
			{ handle, text: 'shared response' },
		]);
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

		await expect(Promise.all([viewportRequest, selectedRequest])).resolves.toEqual([
			{ handle, text: 'selected body survives viewport churn' },
			{ handle, text: 'selected body survives viewport churn' },
		]);
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

		expect(fresh.text).toBe('fresh response');
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
});
