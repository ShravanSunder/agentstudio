import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeWorkerReviewContentMetadata,
	type BridgeWorkerReviewRenderSemantics,
} from './bridge-worker-contracts.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	commitBridgeWorkerReviewContentReadyRenderPatch,
	prepareBridgeWorkerReviewContentRenderJobEvent,
} from './bridge-worker-review-content-ready.js';

describe('Bridge worker review content ready', () => {
	test('publishes only schema-valid surface-typed Review content-ready events', () => {
		// Arrange
		const store = createBridgeCommWorkerStore({
			surface: 'review',
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
			publicationSequence: 11,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: 'item-1',
				publicationSequence: 11,
				surface: 'review',
				workerDerivationEpoch: 7,
			}),
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					text: 'base content\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					text: 'head content\n',
				}),
			],
			semantics: makeRenderSemantics(),
			workerDerivationEpoch: 7,
		});
		if (preparedJobEvent === null) {
			throw new Error('Expected review render job event.');
		}

		// Act
		const contentReadyCommit = commitBridgeWorkerReviewContentReadyRenderPatch({
			preparedJobEvent,
			publicationSequence: 11,
			store,
			workerDerivationEpoch: 7,
		});
		const publications = [
			preparedJobEvent.message,
			contentReadyCommit.preparedMessage.message,
		] as const;

		// Assert
		expect(publications.map(({ kind }) => kind)).toEqual([
			'reviewPierreRenderJob',
			'reviewRenderPatch',
		]);
		expect(publications).toEqual([
			expect.objectContaining({ kind: 'reviewPierreRenderJob', surface: 'review' }),
			expect.objectContaining({ kind: 'reviewRenderPatch', surface: 'review' }),
		]);
		for (const publication of publications) {
			expect(bridgeWorkerServerToMainMessageSchema.safeParse(publication).success).toBe(true);
		}
	});

	test('prepares review Pierre job events without publishing ready before courier acceptance', () => {
		const store = createBridgeCommWorkerStore({
			surface: 'review',
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
			publicationSequence: 11,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: 'item-1',
				publicationSequence: 11,
				surface: 'review',
				workerDerivationEpoch: 7,
			}),
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					text: 'base content\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					text: 'head content\n',
				}),
			],
			semantics: makeRenderSemantics(),
			workerDerivationEpoch: 7,
		});

		expect(result?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'reviewPierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				contentCacheKey:
					'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		expect(result?.message.transferDescriptors).toEqual([
			{
				messageKind: 'reviewPierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: result?.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(result?.transferList).toEqual([]);
		expect(store.getState().paintReadyByItemId.has('item-1')).toBe(false);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 12 })).toBeNull();
	});

	test('commits content-ready slice patches only after the render job is accepted', () => {
		const store = createBridgeCommWorkerStore({
			surface: 'review',
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
			publicationSequence: 11,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: 'item-1',
				publicationSequence: 11,
				surface: 'review',
				workerDerivationEpoch: 7,
			}),
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					text: 'base content\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					text: 'head content\n',
				}),
			],
			semantics: makeRenderSemantics(),
			workerDerivationEpoch: 7,
		});
		if (preparedJobEvent === null) {
			throw new Error('Expected review render job event.');
		}

		const result = commitBridgeWorkerReviewContentReadyRenderPatch({
			preparedJobEvent,
			publicationSequence: 11,
			store,
			workerDerivationEpoch: 7,
		});

		expect(result.touchedKeys).toEqual([
			'byteCache:pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
			'paintReady:item-1',
			'availability:item-1',
		]);
		expect(result.preparedMessage.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			publicationSequence: 11,
			surface: 'review',
			transferDescriptors: [],
			workerDerivationEpoch: 7,
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
			surface: 'review',
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
			publicationSequence: 11,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: 'item-1',
				publicationSequence: 11,
				surface: 'review',
				workerDerivationEpoch: 7,
			}),
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					text: 'base content\n',
				}),
			],
			semantics: makeRenderSemantics(),
			workerDerivationEpoch: 7,
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
	readonly text: string;
}): BridgeWorkerFetchedReviewContentResource {
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		descriptorId: `descriptor-item-1-${props.role}`,
		language: 'swift',
		byteLength: textBytes.byteLength,
		observedSha256: props.role === 'base' ? 'a'.repeat(64) : 'b'.repeat(64),
		requestId: `content-request-item-1-${props.role}`,
		sourceGeneration: 7,
		sourceIdentity: 'review-source-1',
		sourcePosition: 'whole',
		text: props.text,
		textBytes,
	};
}
