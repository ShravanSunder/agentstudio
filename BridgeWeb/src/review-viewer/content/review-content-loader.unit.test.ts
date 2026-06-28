import { describe, expect, test } from 'vitest';

import {
	makeBridgeContentHandle,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeReviewContentRoles,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import {
	loadSelectedReviewItemContent,
	loadSelectedReviewItemContentResources,
} from './review-content-loader.js';
import { createBridgeReviewContentRegistry } from './review-content-registry.js';

describe('review content loader', () => {
	test('loads the selected item through the preferred content handle URL', async () => {
		const requestedUrls: string[] = [];
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: null,
			head: authoritativeContentHandle('item-source', 'head', headTextSha256),
			diff: null,
			file: null,
		});

		const resource = await loadSelectedReviewItemContent({
			reviewPackage,
			selectedItemId: 'item-source',
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('head text');
			},
		});

		expect(resource?.readText()).toBe('head text');
		expect(resource?.handle.role).toBe('head');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
	});

	test('loads selected diff content through base and head handles', async () => {
		const requestedUrls: string[] = [];
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: authoritativeContentHandle('item-source', 'base', baseTextSha256),
			head: authoritativeContentHandle('item-source', 'head', headTextSha256),
			diff: null,
			file: null,
		});

		const resources = await loadSelectedReviewItemContentResources({
			reviewPackage,
			selectedItemId: 'item-source',
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response(url.includes('-base') ? 'base text' : 'head text');
			},
		});

		expect(resources?.base?.readText()).toBe('base text');
		expect(resources?.head?.readText()).toBe('head text');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-base?generation=1',
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
	});

	test('reuses registry content across repeated selected item hydration', async () => {
		const requestedUrls: string[] = [];
		const contentRegistry = createBridgeReviewContentRegistry();
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: authoritativeContentHandle('item-source', 'base', baseTextSha256),
			head: authoritativeContentHandle('item-source', 'head', headTextSha256),
			diff: null,
			file: null,
		});

		const first = await loadSelectedReviewItemContentResources({
			reviewPackage,
			selectedItemId: 'item-source',
			contentRegistry,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response(url.includes('-base') ? 'base text' : 'head text');
			},
		});
		const second = await loadSelectedReviewItemContentResources({
			reviewPackage,
			selectedItemId: 'item-source',
			contentRegistry,
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response(url.includes('-base') ? 'base dupe' : 'head dupe');
			},
		});

		expect(first?.base?.readText()).toBe('base text');
		expect(first?.head?.readText()).toBe('head text');
		expect(second?.base?.readText()).toBe('base text');
		expect(second?.head?.readText()).toBe('head text');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-base?generation=1',
			'agentstudio://resource/review/content/handle-item-source-head?generation=1',
		]);
	});

	test('rejects preview-only selected item content as final content', async () => {
		const previewOnlyHeadHandle: BridgeContentHandle = {
			...makeBridgeContentHandle('item-source', 'head'),
			contentHash: '',
			contentHashAlgorithm: 'git-oid',
			sizeBytes: 9,
		};
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: null,
			head: previewOnlyHeadHandle,
			diff: null,
			file: null,
		});

		await expect(
			loadSelectedReviewItemContent({
				reviewPackage,
				selectedItemId: 'item-source',
				fetchContent: async (): Promise<Response> => new Response('head text'),
			}),
		).rejects.toThrow(
			'Bridge review content resource is preview-only and cannot satisfy final content',
		);
	});

	test('returns null when no selected item is available', async () => {
		const resource = await loadSelectedReviewItemContent({
			reviewPackage: makeBridgeReviewPackage(),
			selectedItemId: null,
			fetchContent: async (): Promise<Response> => new Response('unused'),
		});

		expect(resource).toBeNull();
	});

	test('returns null when selected item id is missing from the package', async () => {
		const resource = await loadSelectedReviewItemContent({
			reviewPackage: makeBridgeReviewPackage(),
			selectedItemId: 'missing-item',
			fetchContent: async (): Promise<Response> => new Response('unused'),
		});

		expect(resource).toBeNull();
	});

	test('returns null when selected item has no available content handles', async () => {
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: null,
			head: null,
			diff: null,
			file: null,
		});

		const resource = await loadSelectedReviewItemContent({
			reviewPackage,
			selectedItemId: 'item-source',
			fetchContent: async (): Promise<Response> => new Response('unused'),
		});

		expect(resource).toBeNull();
	});

	test('surfaces non-ok content responses as loader failures', async () => {
		await expect(
			loadSelectedReviewItemContent({
				reviewPackage: makeBridgeReviewPackage(),
				selectedItemId: 'item-source',
				fetchContent: async (): Promise<Response> =>
					new Response('backend failure', { status: 503 }),
			}),
		).rejects.toThrow('Bridge content request failed: 503');
	});

	test('passes the abort signal through to the content fetch boundary', async () => {
		const abortController = new AbortController();
		abortController.abort();
		const observedSignals: boolean[] = [];

		await expect(
			loadSelectedReviewItemContent({
				reviewPackage: makeBridgeReviewPackage(),
				selectedItemId: 'item-source',
				signal: abortController.signal,
				fetchContent: async (_url: string, init?: RequestInit): Promise<Response> => {
					observedSignals.push(init?.signal?.aborted === true);
					return new Response('', { status: 499 });
				},
			}),
		).rejects.toThrow('Bridge content request failed: 499');
		expect(observedSignals).toEqual([true]);
	});

	test('rejects selected content handles owned by another item before fetch', async () => {
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: null,
			head: makeBridgeContentHandle('item-foreign', 'head'),
			diff: null,
			file: null,
		});
		const requestedUrls: string[] = [];

		await expect(
			loadSelectedReviewItemContent({
				reviewPackage,
				selectedItemId: 'item-source',
				fetchContent: async (url: string): Promise<Response> => {
					requestedUrls.push(url);
					return new Response('must not fetch foreign content');
				},
			}),
		).rejects.toThrow('Bridge content handle does not match selected review item');
		expect(requestedUrls).toEqual([]);
	});

	test('rejects selected content handles from a stale review generation before fetch', async () => {
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: null,
			head: {
				...makeBridgeContentHandle('item-source', 'head'),
				reviewGeneration: 0,
				resourceUrl: 'agentstudio://resource/review/content/handle-item-source-head?generation=0',
			},
			diff: null,
			file: null,
		});
		const requestedUrls: string[] = [];

		await expect(
			loadSelectedReviewItemContent({
				reviewPackage,
				selectedItemId: 'item-source',
				fetchContent: async (url: string): Promise<Response> => {
					requestedUrls.push(url);
					return new Response('must not fetch stale content');
				},
			}),
		).rejects.toThrow('Bridge content handle does not match selected review item');
		expect(requestedUrls).toEqual([]);
	});

	test('loads one-sided file-role resources for added files', async () => {
		const fileHandle: BridgeContentHandle = {
			...makeBridgeContentHandle('item-source', 'head'),
			handleId: 'handle-item-source-file',
			role: 'file',
			resourceUrl: 'agentstudio://resource/review/content/handle-item-source-file?generation=1',
			cacheKey: 'item-source:file',
			contentHash: fileTextSha256,
			contentHashAlgorithm: 'sha256',
		};
		const reviewPackage = packageWithSelectedItemContentRoles({
			base: null,
			head: null,
			diff: null,
			file: fileHandle,
		});
		const requestedUrls: string[] = [];

		const resources = await loadSelectedReviewItemContentResources({
			reviewPackage,
			selectedItemId: 'item-source',
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response('file text');
			},
		});

		expect(resources?.file?.readText()).toBe('file text');
		expect(requestedUrls).toEqual([
			'agentstudio://resource/review/content/handle-item-source-file?generation=1',
		]);
	});
});

const baseTextSha256 = 'sha256:5abd7d8a083e4eb248080f52211eb15f3b785ef1bb1fd9117caa02d6ae81ba69';
const headTextSha256 = 'sha256:1fd3b09376e42af78657b7cb28d101699a1ac7ff4bc9232f32e71bcbdff17b7c';
const fileTextSha256 = 'sha256:448372bbd09f40b8c2da6754df5e29a1580905be745e26723653dea93ab6722e';

function authoritativeContentHandle(
	itemId: string,
	role: 'base' | 'head',
	contentHash: string,
): BridgeContentHandle {
	return {
		...makeBridgeContentHandle(itemId, role),
		contentHash,
		contentHashAlgorithm: 'sha256',
	};
}

function packageWithSelectedItemContentRoles(
	contentRoles: BridgeReviewContentRoles,
): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const selectedItem = reviewPackage.itemsById['item-source'];
	if (selectedItem === undefined) {
		throw new Error('expected item-source fixture item');
	}
	return {
		...reviewPackage,
		itemsById: {
			...reviewPackage.itemsById,
			'item-source': {
				...selectedItem,
				contentRoles,
			},
		},
	};
}
