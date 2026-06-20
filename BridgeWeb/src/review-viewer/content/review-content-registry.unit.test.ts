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
			'agentstudio://resource/content/handle-item-source-head?generation=1',
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

	test('clears cached bodies when active package identity changes', async () => {
		const registry = createBridgeReviewContentRegistry();
		const firstHandle = makeBridgeContentHandle('item-source', 'head');
		const secondHandle: BridgeContentHandle = {
			...firstHandle,
			reviewGeneration: 2,
			resourceUrl: 'agentstudio://resource/content/handle-item-source-head?generation=2&revision=1',
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
			'agentstudio://resource/content/handle-item-source-head?generation=1',
			'agentstudio://resource/content/handle-item-source-head?generation=2&revision=1',
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
			resourceUrl: 'agentstudio://resource/content/handle-item-source-head?revision=4&generation=1',
		};

		expect(canonicalContentResourceKey(handle)).toBe(
			'agentstudio://resource/content/handle-item-source-head?generation=1&revision=4',
		);
	});
});
