import { parseDiffFromFile } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { prepareBridgeMainPierreItemForPresentation } from '../core/comm-worker/bridge-main-pierre-item-adapter.js';
import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
} from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerReviewDisplayPatchEventSchema,
	bridgeWorkerReviewPierreRenderJobEventSchema,
	type BridgeWorkerReviewDisplayPatchEvent,
	type BridgeWorkerReviewPierreRenderJobEvent,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerPierreCourier } from '../core/comm-worker/bridge-worker-pierre-courier.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderJob,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import {
	bridgeWorkerRenderDispositionReceiptSchema,
	type BridgeWorkerRenderDispositionReceipt,
} from '../core/comm-worker/bridge-worker-render-fulfillment.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import { applyBridgeWorkerMessagesToMainRenderSnapshotStore } from './bridge-app-review-render-snapshot-controller.js';

describe('Bridge app Review render snapshot fulfillment admission', () => {
	test('installs one current catalog publication before emitting one queued receipt and replays idempotently', () => {
		// Arrange
		const harness = createFulfillmentAdmissionHarness(100);
		const itemId = 'review-current-item';
		seedReviewCatalog(harness.renderSnapshotStore, {
			epoch: 7,
			itemIds: [itemId],
		});
		const publication = makeReviewPublication({
			itemId,
			publicationSequence: 11,
			workerDerivationEpoch: 7,
		});
		let codeViewItemNotificationCount = 0;
		const unsubscribe = harness.renderSnapshotStore.subscribeReviewCodeViewItem(itemId, () => {
			codeViewItemNotificationCount += 1;
			harness.admissionEvents.push('store:installed');
		});

		// Act
		applyReviewPublication(harness, publication);
		const installedInitialSeed = harness.renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId);
		if (installedInitialSeed === undefined) {
			throw new Error('Expected the Review controller to install its initial main-owned seed.');
		}
		applyReviewPublication(harness, publication);

		// Assert
		expect(installedInitialSeed).not.toBe(publication.job.payload.item);
		expect(installedInitialSeed.version).toBe(1);
		expect(harness.renderFulfillmentCoordinator.isBoundFinalItem(installedInitialSeed)).toBe(true);
		expect(harness.renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId)).toBe(
			installedInitialSeed,
		);
		expect(harness.submittedJobs).toEqual([publication.job]);
		expect(codeViewItemNotificationCount).toBe(1);
		expect(harness.dispositions).toEqual([expectedQueuedDisposition(publication, 100)]);
		expect(harness.storeItemsAtDisposition).toEqual([installedInitialSeed]);
		expect(harness.admissionEvents).toEqual(['store:installed', 'receipt:queued']);

		unsubscribe();
	});

	test('defers a replacement queued receipt until the collapse-preserving final item is bound', () => {
		// Arrange
		const harness = createFulfillmentAdmissionHarness(150);
		const itemId = 'review-replacement-item';
		seedReviewCatalog(harness.renderSnapshotStore, {
			epoch: 7,
			itemIds: [itemId],
		});
		const firstPublication = makeReviewPublication({
			itemId,
			publicationSequence: 1,
			workerDerivationEpoch: 7,
		});
		const secondPublication = makeReviewPublication({
			itemId,
			publicationSequence: 2,
			workerDerivationEpoch: 7,
		});
		applyReviewPublication(harness, firstPublication);
		const firstInstalledItem = harness.renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId);
		if (firstInstalledItem === undefined) {
			throw new Error('Expected the initial Review publication to install a main-owned item.');
		}
		const collapsedLiveItem = {
			...firstInstalledItem,
			collapsed: true,
			version: (firstInstalledItem.version ?? 0) + 1,
		};

		// Act
		applyReviewPublication(harness, secondPublication);

		// Assert: submission alone cannot acknowledge an object that the panel has not bound.
		expect(harness.dispositions.map((receipt) => receipt.disposition)).toEqual([
			'queued',
			'superseded',
		]);
		expect(harness.submittedJobs).toEqual([firstPublication.job, secondPublication.job]);

		// Act: the panel owns the live collapse-aware adaptation and supplies the final object.
		const preparedReplacement = prepareBridgeMainPierreItemForPresentation({
			currentItem: collapsedLiveItem,
			presentationItem: secondPublication.job.payload.item,
		});
		harness.renderFulfillmentCoordinator.bindPublicationItem({
			finalItem: preparedReplacement.item,
			publicationItem: secondPublication.job.payload.item,
			residency: preparedReplacement.residency,
		});

		// Assert
		expect(preparedReplacement.item.collapsed).toBe(true);
		expect(harness.renderFulfillmentCoordinator.isBoundFinalItem(preparedReplacement.item)).toBe(
			true,
		);
		expect(harness.dispositions.at(-1)).toEqual(expectedQueuedDisposition(secondPublication, 150));
	});

	test('terminally rejects a stale Review publication with its full receipt identity instead of installing it', () => {
		// Arrange
		const harness = createFulfillmentAdmissionHarness(200);
		const itemId = 'review-stale-epoch-item';
		seedReviewCatalog(harness.renderSnapshotStore, {
			epoch: 8,
			itemIds: [itemId],
		});
		const publication = makeReviewPublication({
			itemId,
			publicationSequence: 12,
			workerDerivationEpoch: 7,
		});

		// Act
		applyReviewPublication(harness, publication);

		// Assert
		expect(harness.renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId)).toBeUndefined();
		expect(harness.submittedJobs).toEqual([]);
		expect(harness.dispositions).toEqual([expectedRejectedDisposition(publication, 200)]);
		expect(harness.storeItemsAtDisposition).toEqual([undefined]);
		expect(harness.admissionEvents).toEqual(['receipt:rejected']);
	});

	test('terminally rejects a current-epoch publication outside the accepted Review catalog', () => {
		// Arrange
		const harness = createFulfillmentAdmissionHarness(300);
		seedReviewCatalog(harness.renderSnapshotStore, {
			epoch: 9,
			itemIds: ['review-retained-item'],
		});
		const publication = makeReviewPublication({
			itemId: 'review-removed-item',
			publicationSequence: 13,
			workerDerivationEpoch: 9,
		});

		// Act
		applyReviewPublication(harness, publication);

		// Assert
		expect(
			harness.renderSnapshotStore.getReviewCodeViewItemSnapshot(publication.job.itemId),
		).toBeUndefined();
		expect(harness.submittedJobs).toEqual([]);
		expect(harness.dispositions).toEqual([expectedRejectedDisposition(publication, 300)]);
		expect(harness.storeItemsAtDisposition).toEqual([undefined]);
		expect(harness.admissionEvents).toEqual(['receipt:rejected']);
	});
});

interface FulfillmentAdmissionHarness {
	readonly admissionEvents: string[];
	readonly dispositions: BridgeWorkerRenderDispositionReceipt[];
	readonly pierreCourier: BridgeWorkerPierreCourier;
	readonly renderFulfillmentCoordinator: BridgeMainRenderFulfillmentCoordinator;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
	readonly storeItemsAtDisposition: Array<BridgeMainCodeViewItem | undefined>;
	readonly submittedJobs: BridgeWorkerPierreRenderJob[];
}

function createFulfillmentAdmissionHarness(nowMilliseconds: number): FulfillmentAdmissionHarness {
	const admissionEvents: string[] = [];
	const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
	const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
	const storeItemsAtDisposition: Array<BridgeMainCodeViewItem | undefined> = [];
	const submittedJobs: BridgeWorkerPierreRenderJob[] = [];
	const pierreCourier: BridgeWorkerPierreCourier = {
		submit: (job): void => {
			submittedJobs.push(job);
		},
	};
	const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: (_frameHandle): void => {},
		nowMilliseconds: (): number => nowMilliseconds,
		requestAnimationFrame: (_callback): number => {
			throw new Error('Review admission must not schedule paint validation.');
		},
		sendDisposition: (receipt): void => {
			dispositions.push(receipt);
			storeItemsAtDisposition.push(
				renderSnapshotStore.getReviewCodeViewItemSnapshot(receipt.itemId),
			);
			admissionEvents.push(`receipt:${receipt.disposition}`);
		},
	});
	return {
		admissionEvents,
		dispositions,
		pierreCourier,
		renderFulfillmentCoordinator,
		renderSnapshotStore,
		storeItemsAtDisposition,
		submittedJobs,
	};
}

function applyReviewPublication(
	harness: FulfillmentAdmissionHarness,
	publication: BridgeWorkerReviewPierreRenderJobEvent,
): void {
	const applyProps = {
		messages: [publication],
		pierreCourier: harness.pierreCourier,
		renderFulfillmentCoordinator: harness.renderFulfillmentCoordinator,
		renderSnapshotStore: harness.renderSnapshotStore,
	};
	applyBridgeWorkerMessagesToMainRenderSnapshotStore(applyProps);
}

function expectedQueuedDisposition(
	publication: BridgeWorkerReviewPierreRenderJobEvent,
	receivedAtMilliseconds: number,
): BridgeWorkerRenderDispositionReceipt {
	return bridgeWorkerRenderDispositionReceiptSchema.parse({
		...publication.renderReceiptIdentity,
		disposition: 'queued',
		kind: 'render.disposition',
		receivedAtMilliseconds,
	});
}

function expectedRejectedDisposition(
	publication: BridgeWorkerReviewPierreRenderJobEvent,
	receivedAtMilliseconds: number,
): BridgeWorkerRenderDispositionReceipt {
	return bridgeWorkerRenderDispositionReceiptSchema.parse({
		...publication.renderReceiptIdentity,
		disposition: 'rejected',
		kind: 'render.disposition',
		reason: 'stale_submission',
		receivedAtMilliseconds,
		retryAtMilliseconds: receivedAtMilliseconds,
	});
}

interface MakeReviewPublicationProps {
	readonly itemId: string;
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}

function makeReviewPublication(
	props: MakeReviewPublicationProps,
): BridgeWorkerReviewPierreRenderJobEvent {
	const contentCacheKey = `review-cache-${props.publicationSequence}`;
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 4096, maxWindowLines: 20 },
		contentCacheKey,
		contentHash: `review-hash-${props.publicationSequence}`,
		itemId: props.itemId,
		language: 'typescript',
		payload: {
			kind: 'codeViewDiffItem',
			item: {
				bridgeMetadata: {
					cacheKey: contentCacheKey,
					contentRoles: ['base', 'head'],
					contentState: 'hydrated',
					displayPath: `Sources/${props.itemId}.ts`,
					itemId: props.itemId,
					lineCount: 2,
				},
				fileDiff: parseDiffFromFile(
					{
						cacheKey: `${contentCacheKey}:base`,
						contents: 'export const revision = 0;\n',
						name: `Sources/${props.itemId}.ts`,
					},
					{
						cacheKey: `${contentCacheKey}:head`,
						contents: `export const revision = ${props.publicationSequence};\n`,
						name: `Sources/${props.itemId}.ts`,
					},
				),
				id: props.itemId,
				type: 'diff',
				version: props.publicationSequence,
			},
		},
		renderKind: 'reviewDiff',
		window: { endLine: 2, startLine: 1, totalLineCount: 2 },
	});
	return bridgeWorkerReviewPierreRenderJobEventSchema.parse({
		direction: 'serverWorkerToMain',
		job,
		kind: 'reviewPierreRenderJob',
		publicationSequence: props.publicationSequence,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId: props.itemId,
			publicationSequence: props.publicationSequence,
			surface: 'review',
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
		surface: 'review',
		transferDescriptors: [
			{
				byteLength: job.payloadByteLength,
				fieldPath: ['job', 'payload'],
				messageKind: 'reviewPierreRenderJob',
				mode: 'clone',
			},
		],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		workerDerivationEpoch: props.workerDerivationEpoch,
	});
}

function seedReviewCatalog(
	renderSnapshotStore: BridgeMainRenderSnapshotStore,
	props: { readonly epoch: number; readonly itemIds: readonly string[] },
): void {
	renderSnapshotStore.applyReviewDisplayPatchEvent(makeReviewDisplayPatchEvent(props));
}

function makeReviewDisplayPatchEvent(props: {
	readonly epoch: number;
	readonly itemIds: readonly string[];
}): BridgeWorkerReviewDisplayPatchEvent {
	return bridgeWorkerReviewDisplayPatchEventSchema.parse({
		direction: 'serverWorkerToMain',
		epoch: props.epoch,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity: `review-window-epoch-${props.epoch}`,
					status: 'ready',
					summary: {
						additions: 0,
						deletions: 0,
						filesChanged: props.itemIds.length,
						hiddenFileCount: 0,
						visibleFileCount: props.itemIds.length,
					},
					totalItemCount: props.itemIds.length,
					totalTreeRowCount: props.itemIds.length,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: props.itemIds.map((itemId) => ({
						contentFacts: [],
						extentFacts: [],
						metadata: {
							basePath: `${itemId}.ts`,
							changeKind: 'modified',
							contentDescriptorIdsByRole: {},
							contentHashesByRole: {},
							contentRoles: [],
							extension: 'ts',
							fileClass: 'source',
							headPath: `${itemId}.ts`,
							isHiddenByDefault: false,
							itemId,
							language: 'typescript',
							mimeTypes: ['text/plain'],
							provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
							reviewPriority: 'normal',
							reviewState: 'unreviewed',
						},
						metadataWindowIdentity: `review-window-${itemId}`,
					})),
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
		],
		projectionRevision: props.epoch,
		sequence: props.epoch,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	});
}
