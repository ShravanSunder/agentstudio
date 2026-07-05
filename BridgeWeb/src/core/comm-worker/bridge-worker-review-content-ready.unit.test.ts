import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewRenderSemantics,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	commitBridgeWorkerReviewContentReadySlicePatch,
	prepareBridgeWorkerReviewContentRenderJobEvent,
} from './bridge-worker-review-content-ready.js';

describe('Bridge worker review content ready', () => {
	test('prepares review Pierre job events without publishing ready before courier acceptance', () => {
		const baseTextBytes = new ArrayBuffer(40);
		const headTextBytes = new ArrayBuffer(64);
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		});

		const result = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					textBytes: baseTextBytes,
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					textBytes: headTextBytes,
				}),
			],
			semantics: makeRenderSemantics(),
		});

		expect(result?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				contentCacheKey:
					'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
			},
			transferDescriptors: [
				{
					messageKind: 'pierreRenderJob',
					fieldPath: ['job', 'payload', 'baseTextBytes'],
					byteLength: 40,
					mode: 'transfer',
				},
				{
					messageKind: 'pierreRenderJob',
					fieldPath: ['job', 'payload', 'headTextBytes'],
					byteLength: 64,
					mode: 'transfer',
				},
			],
		});
		expect(result?.transferList).toEqual([baseTextBytes, headTextBytes]);
		expect(store.getState().paintReadyByItemId.has('item-1')).toBe(false);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 12 })).toBeNull();
	});

	test('commits content-ready slice patches only after the render job is accepted', () => {
		const baseTextBytes = new ArrayBuffer(40);
		const headTextBytes = new ArrayBuffer(64);
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		});
		const preparedJobEvent = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					textBytes: baseTextBytes,
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					textBytes: headTextBytes,
				}),
			],
			semantics: makeRenderSemantics(),
		});
		if (preparedJobEvent === null) {
			throw new Error('Expected review render job event.');
		}

		const result = commitBridgeWorkerReviewContentReadySlicePatch({
			epoch: 7,
			preparedJobEvent,
			sequence: 11,
			store,
		});

		expect(result.touchedKeys).toEqual([
			'byteCache:pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
			'paintReady:item-1',
			'availability:item-1',
		]);
		expect(result.preparedMessage.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'slicePatch',
			epoch: 7,
			sequence: 11,
			transferDescriptors: [],
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
					payload: {
						contentCacheKey:
							'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
					},
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});
		expect(result.preparedMessage.transferList).toEqual([]);
		expect(store.getState().paintReadyByItemId.get('item-1')).toBe(
			'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
		);
	});

	test('does not mutate the worker store when no complete render job can be planned', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		});

		const result = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					textBytes: new ArrayBuffer(40),
				}),
			],
			semantics: makeRenderSemantics(),
		});

		expect(result).toBeNull();
		expect(store.getState().paintReadyByItemId.has('item-1')).toBe(false);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 12 })).toBeNull();
	});
});

function makeWorkerReviewContentMetadata(itemId: string): BridgeWorkerReviewContentMetadata {
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `${itemId}:base|${itemId}:head`,
		sizeBytes: 1024,
		availableContentRoles: ['base', 'head'],
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

function makeRenderSemantics(
	overrides: Partial<BridgeWorkerReviewRenderSemantics> = {},
): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/item-1.swift',
		basePath: 'Sources/App/item-1.swift',
		headPath: 'Sources/App/item-1.swift',
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
		...overrides,
	};
}

function makeFetchedReviewContentResource(props: {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly textBytes: ArrayBuffer;
}): BridgeWorkerFetchedReviewContentResource {
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		byteLength: props.textBytes.byteLength,
		textBytes: props.textBytes,
	};
}
