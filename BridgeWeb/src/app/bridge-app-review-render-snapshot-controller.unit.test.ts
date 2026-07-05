import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeWorkerPierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerPierreCourier } from '../core/comm-worker/bridge-worker-pierre-courier.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderJob,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	applyBridgeWorkerMessagesToMainRenderSnapshotStore,
	bridgeCommWorkerContentItemsFromReviewPackage,
	createUnsupportedBridgeReviewPierreCourier,
} from './bridge-app-review-render-snapshot-controller.js';

describe('Bridge app review render snapshot controller', () => {
	test('routes worker Pierre render jobs through the courier instead of dropping them', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:abc123',
			contentHash: 'abc123',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 10,
				totalLineCount: 100,
			},
			payload: {
				kind: 'textWindow',
				textBytes: new ArrayBuffer(96),
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});
		const event = {
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'pierreRenderJob',
			job,
		} satisfies BridgeWorkerPierreRenderJobEvent;
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			enqueue: (receivedJob: BridgeWorkerPierreRenderJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
			},
		};

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderSnapshotStore,
		});

		expect(enqueuedJobs).toEqual([job]);
	});

	test('default unsupported courier fails loudly instead of faking enqueue success', () => {
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-unsupported',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:unsupported',
			contentHash: 'unsupported',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 8,
				totalLineCount: 80,
			},
			payload: {
				kind: 'textWindow',
				textBytes: new ArrayBuffer(64),
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});

		expect(() => createUnsupportedBridgeReviewPierreCourier().enqueue(job)).toThrow(
			/before a Pierre adapter was installed/i,
		);
	});

	test('routes only slice patches into the render snapshot store', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			enqueue: (receivedJob: BridgeWorkerPierreRenderJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
			},
		};
		const messages = [
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				status: 'ready',
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'subscription',
				requestId: 'request-subscription',
				subscription: 'reviewContent',
				status: 'subscribed',
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 4,
				sequence: 7,
				patches: [
					{
						slice: 'selection',
						operation: 'upsert',
						payload: {
							selectedItemId: 'item-2',
							source: 'user',
						},
					},
				],
			},
		] satisfies readonly BridgeWorkerServerToMainMessage[];

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages,
			pierreCourier,
			renderSnapshotStore,
		});

		expect(renderSnapshotStore.getSnapshot().selectionSlice).toEqual({
			selectedItemId: 'item-2',
			source: 'user',
		});
		expect(enqueuedJobs).toEqual([]);
	});

	test('maps review package items into worker content metadata without package snapshots', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const contentItems = bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage);

		expect(contentItems).toHaveLength(1);
		expect(contentItems[0]).toMatchObject({
			itemId: 'item-source',
			path: 'Sources/App/View.swift',
			language: 'swift',
			cacheKey: 'item-source:base|item-source:head',
			sizeBytes: 1024,
		});
		expect(contentItems[0]?.contentRoles.head?.resourceUrl).toMatch(/^agentstudio:\/\//);
		expect(JSON.stringify(contentItems)).not.toMatch(/itemsById|orderedItemIds|summary|groups/i);
		expect(bridgeCommWorkerContentItemsFromReviewPackage(null)).toEqual([]);
	});
});
