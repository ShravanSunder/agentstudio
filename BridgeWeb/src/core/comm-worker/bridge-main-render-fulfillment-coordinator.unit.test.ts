import type { PostRenderPhase } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderFulfillmentCoordinator } from './bridge-main-render-fulfillment-coordinator.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerFilePierreRenderJobEventSchema,
	bridgeWorkerReviewPierreRenderJobEventSchema,
	type BridgeWorkerFilePierreRenderJobEvent,
	type BridgeWorkerReviewPierreRenderJobEvent,
} from './bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import {
	bridgeWorkerRenderDispositionReceiptSchema,
	type BridgeWorkerRenderDisposition,
	type BridgeWorkerRenderDispositionReceipt,
	type BridgeWorkerRenderRejectionReason,
} from './bridge-worker-render-fulfillment.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';

type BridgeMainRenderPublication =
	| BridgeWorkerFilePierreRenderJobEvent
	| BridgeWorkerReviewPierreRenderJobEvent;
type BridgeMainRenderPublicationItem = BridgeMainRenderPublication['job']['payload']['item'];

interface BridgeMainRenderedItemReadback {
	readonly element: { readonly isConnected: boolean };
	readonly item: BridgeMainRenderPublicationItem;
}

interface BridgeMainRenderReadbackProps {
	readonly readCurrentItem: () => BridgeMainRenderPublicationItem | undefined;
	readonly readRenderedItem: () => BridgeMainRenderedItemReadback | null;
}

interface BridgeMainRenderFulfillmentCoordinator {
	readonly acceptPublication: (publication: BridgeMainRenderPublication) => void;
	readonly bindPublicationItem: (props: {
		readonly finalItem: BridgeMainRenderPublicationItem;
		readonly publicationItem: BridgeMainRenderPublicationItem;
		readonly residency: 'replaced' | 'reusedPainted';
	}) => void;
	readonly dispose: () => void;
	readonly isBoundFinalItem: (item: BridgeMainRenderPublicationItem) => boolean;
	readonly markPublicationQueued: (publication: BridgeMainRenderPublication) => void;
	readonly observePostRender: (
		props: BridgeMainRenderReadbackProps & {
			readonly contextItem: BridgeMainRenderPublicationItem;
			readonly itemId: string;
			readonly phase: PostRenderPhase;
		},
	) => void;
	readonly reconcilePublication: (
		props: BridgeMainRenderReadbackProps & { readonly itemId: string },
	) => void;
	readonly rejectPublication: (
		publication: BridgeMainRenderPublication,
		reason: BridgeWorkerRenderRejectionReason,
	) => void;
	readonly supersedeItem: (itemId: string, reason: BridgeWorkerRenderRejectionReason) => void;
}

describe('Bridge main render fulfillment coordinator', () => {
	test('defers the queued transition until the submitted publication is bound to its final presentation item', () => {
		// Arrange
		const harness = createCoordinatorHarness(10);
		const publication = makeReviewPublication({ itemId: 'review-item-1', publicationSequence: 1 });
		const publicationItem = publication.job.payload.item;
		const finalItem = {
			...publicationItem,
			version: (publicationItem.version ?? 0) + 1,
		};

		// Act
		harness.coordinator.acceptPublication(publication);
		harness.coordinator.acceptPublication(publication);

		// Assert
		expect(harness.dispositions).toEqual([]);

		// Act
		harness.coordinator.markPublicationQueued(publication);
		harness.coordinator.markPublicationQueued(publication);

		// Assert
		expect(harness.dispositions).toEqual([]);

		// Act
		harness.coordinator.bindPublicationItem({
			finalItem,
			publicationItem,
			residency: 'replaced',
		});

		// Assert
		expect(harness.dispositions).toEqual([expectedDisposition(publication, 'queued', 10)]);
		expect(harness.coordinator.isBoundFinalItem(finalItem)).toBe(true);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);
	});

	test('applies one matching non-unmount post-render and paints only after matching connected frame-time readback', () => {
		// Arrange
		const harness = createCoordinatorHarness(100);
		const publication = makeReviewPublication({ itemId: 'review-item-2', publicationSequence: 2 });
		const publicationItem = publication.job.payload.item;
		const currentItem: BridgeMainRenderPublicationItem | undefined = publicationItem;
		const renderedItem: BridgeMainRenderedItemReadback | null = {
			element: { isConnected: true },
			item: publicationItem,
		};
		const readback = {
			readCurrentItem: (): BridgeMainRenderPublicationItem | undefined => currentItem,
			readRenderedItem: (): BridgeMainRenderedItemReadback | null => renderedItem,
		};
		harness.coordinator.acceptPublication(publication);
		bindPublicationItemAsFinal(harness.coordinator, publication);
		harness.coordinator.markPublicationQueued(publication);

		// Act
		harness.setNowMilliseconds(110);
		harness.coordinator.observePostRender({
			...readback,
			contextItem: publicationItem,
			itemId: publication.job.itemId,
			phase: 'mount',
		});
		harness.coordinator.observePostRender({
			...readback,
			contextItem: publicationItem,
			itemId: publication.job.itemId,
			phase: 'update',
		});
		harness.coordinator.reconcilePublication({
			...readback,
			itemId: publication.job.itemId,
		});

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(publication, 'queued', 100),
			expectedDisposition(publication, 'applied', 110),
		]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([1]);

		// Act
		harness.setNowMilliseconds(120);
		harness.animationFrames.runActiveFrame(1);

		// Assert
		expect(currentItem).toBe(publicationItem);
		expect(renderedItem?.item).toBe(publicationItem);
		expect(harness.dispositions).toEqual([
			expectedDisposition(publication, 'queued', 100),
			expectedDisposition(publication, 'applied', 110),
			expectedDisposition(publication, 'painted', 120),
		]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);
	});

	test('rejects disconnected, replaced-current, and mismatched-rendered frame readbacks as stale attempts', () => {
		for (const [caseIndex, staleReadbackKind] of [
			'disconnected',
			'replaced-current',
			'mismatched-rendered',
		].entries()) {
			// Arrange
			const publicationSequence = caseIndex + 10;
			const queuedAtMilliseconds = 200 + caseIndex * 100;
			const appliedAtMilliseconds = queuedAtMilliseconds + 10;
			const rejectedAtMilliseconds = queuedAtMilliseconds + 20;
			const harness = createCoordinatorHarness(queuedAtMilliseconds);
			const publication = makeReviewPublication({
				itemId: `review-stale-${staleReadbackKind}`,
				publicationSequence,
			});
			const replacementPublication = makeReviewPublication({
				itemId: publication.job.itemId,
				publicationSequence: publicationSequence + 100,
			});
			const publicationItem = publication.job.payload.item;
			const replacementItem = replacementPublication.job.payload.item;
			let currentItem: BridgeMainRenderPublicationItem | undefined = publicationItem;
			let renderedItem: BridgeMainRenderedItemReadback | null = {
				element: { isConnected: true },
				item: publicationItem,
			};
			const readback = {
				readCurrentItem: (): BridgeMainRenderPublicationItem | undefined => currentItem,
				readRenderedItem: (): BridgeMainRenderedItemReadback | null => renderedItem,
			};
			harness.coordinator.acceptPublication(publication);
			bindPublicationItemAsFinal(harness.coordinator, publication);
			harness.coordinator.markPublicationQueued(publication);
			harness.setNowMilliseconds(appliedAtMilliseconds);
			harness.coordinator.observePostRender({
				...readback,
				contextItem: publicationItem,
				itemId: publication.job.itemId,
				phase: 'mount',
			});

			// Act
			switch (staleReadbackKind) {
				case 'disconnected':
					renderedItem = { element: { isConnected: false }, item: publicationItem };
					break;
				case 'replaced-current':
					currentItem = replacementItem;
					break;
				case 'mismatched-rendered':
					renderedItem = { element: { isConnected: true }, item: replacementItem };
					break;
			}
			harness.setNowMilliseconds(rejectedAtMilliseconds);
			harness.animationFrames.runActiveFrame(1);

			// Assert
			expect(harness.dispositions, staleReadbackKind).toEqual([
				expectedDisposition(publication, 'queued', queuedAtMilliseconds),
				expectedDisposition(publication, 'applied', appliedAtMilliseconds),
				expectedDisposition(publication, 'rejected', rejectedAtMilliseconds, 'stale_attempt'),
			]);
			expect(
				harness.dispositions.some((receipt) => receipt.disposition === 'painted'),
				staleReadbackKind,
			).toBe(false);

			// Act: browser callbacks may arrive again after cancellation or terminal settlement.
			harness.animationFrames.invokeHistoricalFrame(1);
			harness.animationFrames.invokeHistoricalFrame(1);
			harness.coordinator.observePostRender({
				...readback,
				contextItem: publicationItem,
				itemId: publication.job.itemId,
				phase: 'update',
			});
			harness.coordinator.reconcilePublication({
				...readback,
				itemId: publication.job.itemId,
			});

			// Assert
			expect(harness.dispositions, `${staleReadbackKind}:late-callback`).toHaveLength(3);
			expect(harness.animationFrames.activeFrameHandles()).toEqual([]);
		}
	});

	test('supersedes an applied receipt before queueing its same-item replacement and ignores old callbacks', () => {
		// Arrange
		const harness = createCoordinatorHarness(400);
		const oldPublication = makeReviewPublication({
			itemId: 'review-replaced-item',
			publicationSequence: 20,
		});
		const newPublication = makeReviewPublication({
			itemId: 'review-replaced-item',
			publicationSequence: 21,
		});
		const oldItem = oldPublication.job.payload.item;
		const newItem = newPublication.job.payload.item;
		const oldReadback = connectedReadback(oldItem);
		const newReadback = connectedReadback(newItem);
		harness.coordinator.acceptPublication(oldPublication);
		bindPublicationItemAsFinal(harness.coordinator, oldPublication);
		harness.coordinator.markPublicationQueued(oldPublication);
		harness.setNowMilliseconds(410);
		harness.coordinator.observePostRender({
			...oldReadback,
			contextItem: oldItem,
			itemId: oldPublication.job.itemId,
			phase: 'mount',
		});

		// Act
		harness.setNowMilliseconds(420);
		harness.coordinator.acceptPublication(newPublication);
		bindPublicationItemAsFinal(harness.coordinator, newPublication);
		harness.coordinator.markPublicationQueued(newPublication);

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(oldPublication, 'queued', 400),
			expectedDisposition(oldPublication, 'applied', 410),
			expectedDisposition(oldPublication, 'superseded', 420, 'stale_submission'),
			expectedDisposition(newPublication, 'queued', 420),
		]);
		expect(harness.animationFrames.cancelledFrameHandles()).toEqual([1]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);

		// Act: neither the cancelled frame nor a late Pierre callback for the old item may settle new work.
		harness.animationFrames.invokeHistoricalFrame(1);
		harness.coordinator.observePostRender({
			...oldReadback,
			contextItem: oldItem,
			itemId: oldPublication.job.itemId,
			phase: 'update',
		});

		// Assert
		expect(harness.dispositions).toHaveLength(4);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);

		// Act
		harness.setNowMilliseconds(430);
		harness.coordinator.observePostRender({
			...newReadback,
			contextItem: newItem,
			itemId: newPublication.job.itemId,
			phase: 'mount',
		});
		harness.setNowMilliseconds(440);
		harness.animationFrames.runActiveFrame(2);

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(oldPublication, 'queued', 400),
			expectedDisposition(oldPublication, 'applied', 410),
			expectedDisposition(oldPublication, 'superseded', 420, 'stale_submission'),
			expectedDisposition(newPublication, 'queued', 420),
			expectedDisposition(newPublication, 'applied', 430),
			expectedDisposition(newPublication, 'painted', 440),
		]);
	});

	test('rejects unaccepted stale work and makes explicit supersession and disposal terminal exactly once', () => {
		// Arrange
		const harness = createCoordinatorHarness(500);
		const rejectedPublication = makeReviewPublication({
			itemId: 'review-unaccepted',
			publicationSequence: 30,
		});
		const explicitlySupersededPublication = makeReviewPublication({
			itemId: 'review-explicitly-superseded',
			publicationSequence: 31,
		});
		const appliedAtDisposePublication = makeReviewPublication({
			itemId: 'review-applied-at-dispose',
			publicationSequence: 32,
		});
		const queuedAtDisposePublication = makeReviewPublication({
			itemId: 'review-queued-at-dispose',
			publicationSequence: 33,
		});

		// Act
		harness.coordinator.rejectPublication(rejectedPublication, 'stale_attempt');
		harness.coordinator.acceptPublication(explicitlySupersededPublication);
		bindPublicationItemAsFinal(harness.coordinator, explicitlySupersededPublication);
		harness.coordinator.markPublicationQueued(explicitlySupersededPublication);
		harness.setNowMilliseconds(510);
		harness.coordinator.supersedeItem(
			explicitlySupersededPublication.job.itemId,
			'stale_submission',
		);
		harness.coordinator.acceptPublication(appliedAtDisposePublication);
		bindPublicationItemAsFinal(harness.coordinator, appliedAtDisposePublication);
		harness.coordinator.markPublicationQueued(appliedAtDisposePublication);
		harness.coordinator.acceptPublication(queuedAtDisposePublication);
		bindPublicationItemAsFinal(harness.coordinator, queuedAtDisposePublication);
		harness.coordinator.markPublicationQueued(queuedAtDisposePublication);
		harness.setNowMilliseconds(520);
		const appliedAtDisposeItem = appliedAtDisposePublication.job.payload.item;
		harness.coordinator.observePostRender({
			...connectedReadback(appliedAtDisposeItem),
			contextItem: appliedAtDisposeItem,
			itemId: appliedAtDisposePublication.job.itemId,
			phase: 'mount',
		});

		// Assert
		expect(harness.animationFrames.activeFrameHandles()).toEqual([1]);

		// Act
		harness.setNowMilliseconds(530);
		harness.coordinator.dispose();
		harness.coordinator.dispose();
		harness.animationFrames.invokeHistoricalFrame(1);

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(rejectedPublication, 'rejected', 500, 'stale_attempt'),
			expectedDisposition(explicitlySupersededPublication, 'queued', 500),
			expectedDisposition(explicitlySupersededPublication, 'superseded', 510, 'stale_submission'),
			expectedDisposition(appliedAtDisposePublication, 'queued', 510),
			expectedDisposition(queuedAtDisposePublication, 'queued', 510),
			expectedDisposition(appliedAtDisposePublication, 'applied', 520),
			expectedDisposition(appliedAtDisposePublication, 'superseded', 530, 'stale_submission'),
			expectedDisposition(queuedAtDisposePublication, 'superseded', 530, 'stale_submission'),
		]);
		expect(harness.animationFrames.cancelledFrameHandles()).toEqual([1]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);
	});

	test('keeps same-item File and Review coordinators isolated by exact publication item identity', () => {
		// Arrange
		const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
		let nowMilliseconds = 600;
		const reviewAnimationFrames = createControlledAnimationFrames();
		const fileAnimationFrames = createControlledAnimationFrames();
		const reviewCoordinator = createCoordinator({
			animationFrames: reviewAnimationFrames,
			dispositions,
			nowMilliseconds: (): number => nowMilliseconds,
		});
		const fileCoordinator = createCoordinator({
			animationFrames: fileAnimationFrames,
			dispositions,
			nowMilliseconds: (): number => nowMilliseconds,
		});
		const reviewPublication = makeReviewPublication({
			itemId: 'shared-surface-item',
			publicationSequence: 40,
		});
		const filePublication = makeFilePublication({
			itemId: 'shared-surface-item',
			publicationSequence: 41,
		});
		const reviewItem = reviewPublication.job.payload.item;
		const fileItem = filePublication.job.payload.item;
		reviewCoordinator.acceptPublication(reviewPublication);
		bindPublicationItemAsFinal(reviewCoordinator, reviewPublication);
		reviewCoordinator.markPublicationQueued(reviewPublication);
		fileCoordinator.acceptPublication(filePublication);
		bindPublicationItemAsFinal(fileCoordinator, filePublication);
		fileCoordinator.markPublicationQueued(filePublication);

		// Act: the item id matches File, but the Pierre callback object belongs to Review.
		nowMilliseconds = 610;
		fileCoordinator.observePostRender({
			...connectedReadback(reviewItem),
			contextItem: reviewItem,
			itemId: filePublication.job.itemId,
			phase: 'mount',
		});

		// Assert
		expect(dispositions).toEqual([
			expectedDisposition(reviewPublication, 'queued', 600),
			expectedDisposition(filePublication, 'queued', 600),
		]);
		expect(fileAnimationFrames.activeFrameHandles()).toEqual([]);
		expect(reviewAnimationFrames.activeFrameHandles()).toEqual([]);

		// Act
		reviewCoordinator.observePostRender({
			...connectedReadback(reviewItem),
			contextItem: reviewItem,
			itemId: reviewPublication.job.itemId,
			phase: 'mount',
		});
		fileCoordinator.observePostRender({
			...connectedReadback(fileItem),
			contextItem: fileItem,
			itemId: filePublication.job.itemId,
			phase: 'update',
		});
		nowMilliseconds = 620;
		reviewAnimationFrames.runActiveFrame(1);
		fileAnimationFrames.runActiveFrame(1);

		// Assert
		expect(dispositions).toEqual([
			expectedDisposition(reviewPublication, 'queued', 600),
			expectedDisposition(filePublication, 'queued', 600),
			expectedDisposition(reviewPublication, 'applied', 610),
			expectedDisposition(filePublication, 'applied', 610),
			expectedDisposition(reviewPublication, 'painted', 620),
			expectedDisposition(filePublication, 'painted', 620),
		]);
		expect(
			dispositions
				.filter((receipt) => receipt.disposition === 'painted')
				.map((receipt) => ({
					attemptId: receipt.attemptId,
					surface: receipt.surface,
				})),
		).toEqual([
			{ attemptId: reviewPublication.renderReceiptIdentity.attemptId, surface: 'review' },
			{ attemptId: filePublication.renderReceiptIdentity.attemptId, surface: 'file' },
		]);
	});

	test('binds a changed publication only from its exact raw item, then rejects raw callbacks', () => {
		// Arrange
		const harness = createCoordinatorHarness(700);
		const publication = makeReviewPublication({
			itemId: 'review-main-adapted-item',
			publicationSequence: 50,
		});
		const publicationItem = publication.job.payload.item;
		const finalItem = {
			...publicationItem,
			collapsed: true,
			version: (publicationItem.version ?? 0) + 1,
		} satisfies BridgeMainRenderPublicationItem;
		const mismatchedPublicationItem = cloneReviewPublicationItem(publicationItem);
		const mismatchedFinalItem = {
			...mismatchedPublicationItem,
			collapsed: true,
			version: (mismatchedPublicationItem.version ?? 0) + 1,
		} satisfies BridgeMainRenderPublicationItem;
		harness.coordinator.acceptPublication(publication);
		harness.coordinator.markPublicationQueued(publication);

		// Assert: accepting the raw publication does not bind the adapted final item.
		expect(harness.coordinator.isBoundFinalItem(finalItem)).toBe(false);

		// Act: a structurally equal clone is not the exact pending raw publication object.
		harness.coordinator.bindPublicationItem({
			finalItem: mismatchedFinalItem,
			publicationItem: mismatchedPublicationItem,
			residency: 'replaced',
		});
		harness.coordinator.observePostRender({
			...connectedReadback(mismatchedFinalItem),
			contextItem: mismatchedFinalItem,
			itemId: publication.job.itemId,
			phase: 'update',
		});

		// Assert
		expect(harness.dispositions).toEqual([]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);

		// Act: bind with the exact pending raw publication object.
		harness.coordinator.bindPublicationItem({
			finalItem,
			publicationItem,
			residency: 'replaced',
		});

		// Assert: binding tracks only the exact final object, never the raw publication object.
		expect(harness.coordinator.isBoundFinalItem(publicationItem)).toBe(false);
		expect(harness.coordinator.isBoundFinalItem(finalItem)).toBe(true);
		expect(harness.dispositions).toEqual([expectedDisposition(publication, 'queued', 700)]);

		// Act: the worker publication object is no longer the exact item handed to Pierre.
		harness.setNowMilliseconds(710);
		harness.coordinator.observePostRender({
			...connectedReadback(publicationItem),
			contextItem: publicationItem,
			itemId: publication.job.itemId,
			phase: 'update',
		});

		// Assert
		expect(harness.dispositions).toEqual([expectedDisposition(publication, 'queued', 700)]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([]);

		// Act: only the exact final adapted object plus public readback can settle the attempt.
		harness.coordinator.observePostRender({
			...connectedReadback(finalItem),
			contextItem: finalItem,
			itemId: publication.job.itemId,
			phase: 'update',
		});

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(publication, 'queued', 700),
			expectedDisposition(publication, 'applied', 710),
		]);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([1]);

		// Act
		harness.setNowMilliseconds(720);
		harness.animationFrames.runActiveFrame(1);

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(publication, 'queued', 700),
			expectedDisposition(publication, 'applied', 710),
			expectedDisposition(publication, 'painted', 720),
		]);
	});

	test('settles an equal-fingerprint retry from exact connected painted residency without another post-render callback', () => {
		// Arrange: prove one exact final item through the normal replaced-item path first.
		const harness = createCoordinatorHarness(800);
		const firstPublication = makeReviewPublication({
			itemId: 'review-reused-painted-item',
			publicationSequence: 60,
		});
		const firstPublicationItem = firstPublication.job.payload.item;
		const paintedFinalItem = {
			...firstPublicationItem,
			collapsed: true,
			version: (firstPublicationItem.version ?? 0) + 1,
		} satisfies BridgeMainRenderPublicationItem;
		harness.coordinator.acceptPublication(firstPublication);
		harness.coordinator.markPublicationQueued(firstPublication);
		harness.coordinator.bindPublicationItem({
			finalItem: paintedFinalItem,
			publicationItem: firstPublicationItem,
			residency: 'replaced',
		});
		harness.setNowMilliseconds(810);
		harness.coordinator.observePostRender({
			...connectedReadback(paintedFinalItem),
			contextItem: paintedFinalItem,
			itemId: firstPublication.job.itemId,
			phase: 'mount',
		});
		harness.setNowMilliseconds(820);
		harness.animationFrames.runActiveFrame(1);
		const retryPublication = cloneReviewPublicationForRetry(firstPublication);
		const retryPublicationItem = retryPublication.job.payload.item;
		expect(retryPublicationItem).not.toBe(firstPublicationItem);
		expect(retryPublication.renderReceiptIdentity).toEqual({
			...firstPublication.renderReceiptIdentity,
			attemptId: 'attempt-reused-painted-retry',
		});

		// Act: bind the fresh retry attempt to the exact already-painted final object.
		harness.setNowMilliseconds(830);
		harness.coordinator.acceptPublication(retryPublication);
		harness.coordinator.markPublicationQueued(retryPublication);
		harness.coordinator.bindPublicationItem({
			finalItem: paintedFinalItem,
			publicationItem: retryPublicationItem,
			residency: 'reusedPainted',
		});
		harness.setNowMilliseconds(840);
		harness.coordinator.reconcilePublication({
			...connectedReadback(paintedFinalItem),
			itemId: retryPublication.job.itemId,
		});

		// Assert: no synthetic onPostRender call is needed for equal connected residency.
		expect(harness.dispositions).toEqual([
			expectedDisposition(firstPublication, 'queued', 800),
			expectedDisposition(firstPublication, 'applied', 810),
			expectedDisposition(firstPublication, 'painted', 820),
			expectedDisposition(retryPublication, 'queued', 830),
			expectedDisposition(retryPublication, 'applied', 840),
		]);
		expect(harness.coordinator.isBoundFinalItem(paintedFinalItem)).toBe(true);
		expect(harness.animationFrames.activeFrameHandles()).toEqual([2]);

		// Act
		harness.setNowMilliseconds(850);
		harness.animationFrames.runActiveFrame(2);

		// Assert
		expect(harness.dispositions).toEqual([
			expectedDisposition(firstPublication, 'queued', 800),
			expectedDisposition(firstPublication, 'applied', 810),
			expectedDisposition(firstPublication, 'painted', 820),
			expectedDisposition(retryPublication, 'queued', 830),
			expectedDisposition(retryPublication, 'applied', 840),
			expectedDisposition(retryPublication, 'painted', 850),
		]);
	});
});

interface CreateCoordinatorProps {
	readonly animationFrames: ControlledAnimationFrames;
	readonly dispositions: BridgeWorkerRenderDispositionReceipt[];
	readonly nowMilliseconds: () => number;
}

function createCoordinator(props: CreateCoordinatorProps): BridgeMainRenderFulfillmentCoordinator {
	return createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: props.animationFrames.cancelAnimationFrame,
		nowMilliseconds: props.nowMilliseconds,
		requestAnimationFrame: props.animationFrames.requestAnimationFrame,
		sendDisposition: (receipt): void => {
			props.dispositions.push(receipt);
		},
	});
}

interface CoordinatorHarness {
	readonly animationFrames: ControlledAnimationFrames;
	readonly coordinator: BridgeMainRenderFulfillmentCoordinator;
	readonly dispositions: BridgeWorkerRenderDispositionReceipt[];
	readonly setNowMilliseconds: (nextNowMilliseconds: number) => void;
}

function createCoordinatorHarness(initialNowMilliseconds: number): CoordinatorHarness {
	let nowMilliseconds = initialNowMilliseconds;
	const animationFrames = createControlledAnimationFrames();
	const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
	return {
		animationFrames,
		coordinator: createCoordinator({
			animationFrames,
			dispositions,
			nowMilliseconds: (): number => nowMilliseconds,
		}),
		dispositions,
		setNowMilliseconds: (nextNowMilliseconds): void => {
			nowMilliseconds = nextNowMilliseconds;
		},
	};
}

interface ControlledAnimationFrames {
	readonly activeFrameHandles: () => readonly number[];
	readonly cancelAnimationFrame: (frameHandle: number) => void;
	readonly cancelledFrameHandles: () => readonly number[];
	readonly invokeHistoricalFrame: (frameHandle: number) => void;
	readonly requestAnimationFrame: (callback: FrameRequestCallback) => number;
	readonly runActiveFrame: (frameHandle: number) => void;
}

function createControlledAnimationFrames(): ControlledAnimationFrames {
	let nextFrameHandle = 1;
	const activeCallbacksByFrameHandle = new Map<number, FrameRequestCallback>();
	const historicalCallbacksByFrameHandle = new Map<number, FrameRequestCallback>();
	const cancelledFrameHandles: number[] = [];
	const callbackForHandle = (frameHandle: number): FrameRequestCallback => {
		const callback = historicalCallbacksByFrameHandle.get(frameHandle);
		if (callback === undefined) {
			throw new Error(`Expected animation frame ${frameHandle} to have been scheduled.`);
		}
		return callback;
	};
	return {
		activeFrameHandles: (): readonly number[] => [...activeCallbacksByFrameHandle.keys()],
		cancelAnimationFrame: (frameHandle): void => {
			cancelledFrameHandles.push(frameHandle);
			activeCallbacksByFrameHandle.delete(frameHandle);
		},
		cancelledFrameHandles: (): readonly number[] => cancelledFrameHandles,
		invokeHistoricalFrame: (frameHandle): void => {
			callbackForHandle(frameHandle)(16.67);
		},
		requestAnimationFrame: (callback): number => {
			const frameHandle = nextFrameHandle;
			nextFrameHandle += 1;
			activeCallbacksByFrameHandle.set(frameHandle, callback);
			historicalCallbacksByFrameHandle.set(frameHandle, callback);
			return frameHandle;
		},
		runActiveFrame: (frameHandle): void => {
			if (!activeCallbacksByFrameHandle.delete(frameHandle)) {
				throw new Error(`Expected animation frame ${frameHandle} to be active.`);
			}
			callbackForHandle(frameHandle)(16.67);
		},
	};
}

function connectedReadback(item: BridgeMainRenderPublicationItem): BridgeMainRenderReadbackProps {
	return {
		readCurrentItem: (): BridgeMainRenderPublicationItem => item,
		readRenderedItem: (): BridgeMainRenderedItemReadback => ({
			element: { isConnected: true },
			item,
		}),
	};
}

function bindPublicationItemAsFinal(
	coordinator: BridgeMainRenderFulfillmentCoordinator,
	publication: BridgeMainRenderPublication,
): void {
	const publicationItem = publication.job.payload.item;
	coordinator.bindPublicationItem({
		finalItem: publicationItem,
		publicationItem,
		residency: 'replaced',
	});
}

function expectedDisposition(
	publication: BridgeMainRenderPublication,
	disposition: BridgeWorkerRenderDisposition,
	receivedAtMilliseconds: number,
	reason?: BridgeWorkerRenderRejectionReason,
): BridgeWorkerRenderDispositionReceipt {
	if (disposition === 'rejected' || disposition === 'superseded') {
		if (reason === undefined) {
			throw new Error(`Expected ${disposition} receipt to declare a reason.`);
		}
		return bridgeWorkerRenderDispositionReceiptSchema.parse({
			...publication.renderReceiptIdentity,
			disposition,
			kind: 'render.disposition',
			reason,
			receivedAtMilliseconds,
			retryAtMilliseconds: receivedAtMilliseconds,
		});
	}
	return bridgeWorkerRenderDispositionReceiptSchema.parse({
		...publication.renderReceiptIdentity,
		disposition,
		kind: 'render.disposition',
		receivedAtMilliseconds,
	});
}

interface MakePublicationProps {
	readonly itemId: string;
	readonly publicationSequence: number;
}

function makeReviewPublication(
	props: MakePublicationProps,
): BridgeWorkerReviewPierreRenderJobEvent {
	const contentCacheKey = `review-cache-${props.publicationSequence}`;
	return bridgeWorkerReviewPierreRenderJobEventSchema.parse({
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'reviewPierreRenderJob',
		job: buildBridgeWorkerPierreRenderJob({
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
					fileDiff: {
						additionLines: [`export const revision = ${props.publicationSequence};`],
						deletionLines: ['export const revision = 0;'],
						hunks: [],
						isPartial: false,
						name: `Sources/${props.itemId}.ts`,
						splitLineCount: 2,
						type: 'change',
						unifiedLineCount: 2,
					},
					id: props.itemId,
					type: 'diff',
					version: props.publicationSequence,
				},
			},
			renderKind: 'reviewDiff',
			window: { endLine: 2, startLine: 1, totalLineCount: 2 },
		}),
		publicationSequence: props.publicationSequence,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId: props.itemId,
			publicationSequence: props.publicationSequence,
			surface: 'review',
			workerDerivationEpoch: 7,
		}),
		surface: 'review',
		workerDerivationEpoch: 7,
	});
}

function makeFilePublication(props: MakePublicationProps): BridgeWorkerFilePierreRenderJobEvent {
	const contentCacheKey = `file-cache-${props.publicationSequence}`;
	return bridgeWorkerFilePierreRenderJobEventSchema.parse({
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'filePierreRenderJob',
		job: buildBridgeWorkerPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 4096, maxWindowLines: 20 },
			contentCacheKey,
			contentHash: `file-hash-${props.publicationSequence}`,
			itemId: props.itemId,
			language: 'typescript',
			payload: {
				kind: 'codeViewFileItem',
				item: {
					bridgeMetadata: {
						cacheKey: contentCacheKey,
						contentRoles: ['file'],
						contentState: 'hydrated',
						displayPath: `Sources/${props.itemId}.ts`,
						itemId: props.itemId,
						lineCount: 1,
					},
					file: {
						cacheKey: contentCacheKey,
						contents: `export const fileRevision = ${props.publicationSequence};\n`,
						lang: 'typescript',
						name: `Sources/${props.itemId}.ts`,
					},
					id: props.itemId,
					type: 'file',
					version: props.publicationSequence,
				},
			},
			renderKind: 'fileText',
			window: { endLine: 1, startLine: 1, totalLineCount: 1 },
		}),
		publicationSequence: props.publicationSequence,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId: props.itemId,
			publicationSequence: props.publicationSequence,
			surface: 'file',
			workerDerivationEpoch: 11,
		}),
		surface: 'file',
		workerDerivationEpoch: 11,
	});
}

function cloneReviewPublicationForRetry(
	publication: BridgeWorkerReviewPierreRenderJobEvent,
): BridgeWorkerReviewPierreRenderJobEvent {
	const publicationItem = publication.job.payload.item;
	const clonedPublicationItem = cloneReviewPublicationItem(publicationItem);
	return bridgeWorkerReviewPierreRenderJobEventSchema.parse({
		...publication,
		job: {
			...publication.job,
			payload: {
				...publication.job.payload,
				item: clonedPublicationItem,
			},
		},
		renderReceiptIdentity: {
			...publication.renderReceiptIdentity,
			attemptId: 'attempt-reused-painted-retry',
		},
	});
}

function cloneReviewPublicationItem(
	publicationItem: BridgeWorkerReviewPierreRenderJobEvent['job']['payload']['item'],
): BridgeWorkerReviewPierreRenderJobEvent['job']['payload']['item'] {
	if (publicationItem.type !== 'diff') {
		throw new Error('Review publication fixture requires a diff item.');
	}
	return {
		...publicationItem,
		bridgeMetadata: {
			...publicationItem.bridgeMetadata,
			contentRoles: [...publicationItem.bridgeMetadata.contentRoles],
		},
		fileDiff: {
			...publicationItem.fileDiff,
			additionLines: [...publicationItem.fileDiff.additionLines],
			deletionLines: [...publicationItem.fileDiff.deletionLines],
			hunks: [...publicationItem.fileDiff.hunks],
		},
	};
}
