import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createBridgeWorkerSequenceCounter,
	createDeferredReviewContentStream,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeImmediateReviewContentStream,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	openReviewContentFromDescriptorMap,
	reviewContentFixtureByDescriptorId,
	type DeferredReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import {
	createTrackedBridgeWorkerReviewContentOpen,
	drainBridgeWorkerVisibleDemandRuntimeUntilQuiescent,
	registerBridgeRuntimeWithInitialReviewSource,
} from './bridge-comm-worker-runtime-protocol.visible-demand.test-support.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type { BridgeWorkerReviewPierreRenderJobEvent } from './bridge-worker-contracts.js';
import type { BridgeWorkerReviewContentOpen } from './bridge-worker-review-content-fetch.js';

describe('Bridge comm worker runtime Review hover demand', () => {
	test('warms only the current hovered item speculatively and does not refetch ready content', async () => {
		// Arrange
		const fixture = await createHoverRuntimeFixture({ itemIds: ['hover-a', 'hover-b'] });

		// Act: replace hover A with B before the preparation pump runs.
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 5,
				hoveredItemId: 'hover-a',
				requestId: 'request-hover-a',
				surface: 'review',
			}),
		);
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 6,
				hoveredItemId: 'hover-b',
				requestId: 'request-hover-b',
				surface: 'review',
			}),
		);
		await drainHoverRuntimeUntilQuiescent(fixture);
		const openedDescriptorCountAfterWarm = fixture.trackedContentOpen.openedDescriptorIds.length;
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 7,
				hoveredItemId: null,
				requestId: 'request-hover-exit',
				surface: 'review',
			}),
		);
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 8,
				hoveredItemId: 'hover-b',
				requestId: 'request-hover-b-ready',
				surface: 'review',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(fixture.trackedContentOpen.openedDescriptorIds).toHaveLength(2);
		expect(openedDescriptorCountAfterWarm).toBe(2);
		expect(
			fixture.trackedContentOpen.openedDescriptorIds.every((descriptorId) =>
				descriptorId.includes('hover-b'),
			),
		).toBe(true);
		expect(reviewRenderJobs(fixture)).toEqual([
			expect.objectContaining({
				bridgeDemandRank: { lane: 'speculative', priority: 1 },
				itemId: 'hover-b',
			}),
		]);
	});

	test('rearms unchanged hover membership after higher-priority selected work completes', async () => {
		// Arrange
		const deferredHoverStreamsByDescriptorId = new Map<string, DeferredReviewContentStream>();
		const abortedHoverSignals: AbortSignal[] = [];
		const fixture = await createHoverRuntimeFixture({
			itemIds: ['selected-a', 'hover-b'],
			openReviewContent: (descriptor, abortSignal) => {
				if (
					descriptor.itemId === 'hover-b' &&
					!deferredHoverStreamsByDescriptorId.has(descriptor.descriptorId)
				) {
					const deferredStream = createDeferredReviewContentStream(descriptor);
					deferredHoverStreamsByDescriptorId.set(descriptor.descriptorId, deferredStream);
					abortedHoverSignals.push(abortSignal);
					return deferredStream.stream;
				}
				const contentFixture = reviewContentFixtureByDescriptorId.get(descriptor.descriptorId);
				if (contentFixture === undefined) {
					throw new Error(`Unexpected Review content descriptor ${descriptor.descriptorId}.`);
				}
				return makeImmediateReviewContentStream(descriptor, contentFixture.text);
			},
		});

		// Act: start hover B, then select A while B's speculative fetch is suspended.
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 5,
				hoveredItemId: 'hover-b',
				requestId: 'request-hover-b-before-selection',
				surface: 'review',
			}),
		);
		const initialHoverDrain = assertBridgeCommWorkerPreparationDrain(
			fixture.scheduledDrains.shift(),
		);
		const initialHoverDrainCompletion = initialHoverDrain();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredHoverStreamsByDescriptorId.size).toBe(2);
		fixture.dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 6,
				requestId: 'request-select-a-over-hover-b',
				selectedItemId: 'selected-a',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		for (const deferredStream of deferredHoverStreamsByDescriptorId.values()) {
			deferredStream.resolve('cancelled stale hover body');
		}
		await initialHoverDrainCompletion;
		await drainHoverRuntimeUntilQuiescent(fixture);

		// Assert: selected publishes first, then unchanged hover B is re-derived speculatively.
		expect(abortedHoverSignals).toHaveLength(2);
		expect(abortedHoverSignals.every((signal) => signal.aborted)).toBe(true);
		expect(reviewRenderJobs(fixture).map((job) => [job.itemId, job.bridgeDemandRank.lane])).toEqual(
			[
				['selected-a', 'selected'],
				['hover-b', 'speculative'],
			],
		);
		expect(
			fixture.trackedContentOpen.openedDescriptorIds.filter((descriptorId) =>
				descriptorId.includes('hover-b'),
			),
		).toHaveLength(4);
		expect(fixture.pump.getPendingWorkIds()).toEqual([]);
		expect(fixture.trackedContentOpen.pendingCompletions()).toEqual([]);
		expect(fixture.scheduledDrains).toEqual([]);
	});

	test('terminalizes a failed speculative fetch without an automatic retry loop', async () => {
		// Arrange
		let speculativeOpenCount = 0;
		const fixture = await createHoverRuntimeFixture({
			itemIds: ['hover-failure'],
			openReviewContent: (descriptor) => {
				speculativeOpenCount += 1;
				return {
					contentKind: 'review.content',
					contentRequestId: `failed-content-request-${descriptor.descriptorId}`,
					frames: emptyReviewContentFrameSequence(),
					terminal: Promise.resolve({
						code: 'internal',
						contentKind: 'review.content',
						descriptorId: descriptor.descriptorId,
						kind: 'error',
						retryable: false,
						safeMessage: 'intentional speculative fetch failure',
					}),
				};
			},
		});

		// Act
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 5,
				hoveredItemId: 'hover-failure',
				requestId: 'request-hover-failure-first',
				surface: 'review',
			}),
		);
		await drainHoverRuntimeUntilQuiescent(fixture);

		// Assert
		expect(speculativeOpenCount).toBe(2);
		expect(
			fixture.postedMessages
				.map(({ message }) => message)
				.filter(
					(message) =>
						message.kind === 'reviewRenderPatch' &&
						message.patches.some(
							(patch) =>
								patch.slice === 'contentAvailability' &&
								patch.operation === 'upsert' &&
								patch.payload.reason === 'load_failed' &&
								patch.payload.state === 'failed',
						),
				),
		).toHaveLength(1);
		expect(fixture.scheduledDrains).toEqual([]);
		expect(fixture.pump.getPendingWorkIds()).toEqual([]);
		fixture.dispatch.message(
			encodeBridgeWorkerHoverCommand({
				epoch: 6,
				hoveredItemId: 'hover-failure',
				requestId: 'request-hover-failure-unchanged',
				surface: 'review',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(speculativeOpenCount).toBe(2);
		expect(fixture.scheduledDrains).toEqual([]);
		expect(fixture.pump.getPendingWorkIds()).toEqual([]);
	});
});

type RecordingBridgeCommWorkerPort = ReturnType<typeof createRecordingBridgeCommWorkerPort>;

interface HoverRuntimeFixture {
	readonly dispatch: RecordingBridgeCommWorkerPort['dispatch'];
	readonly postedMessages: RecordingBridgeCommWorkerPort['postedMessages'];
	readonly pump: ReturnType<typeof createWorkerContentPreparationPump>;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
	readonly trackedContentOpen: ReturnType<typeof createTrackedBridgeWorkerReviewContentOpen>;
}

async function createHoverRuntimeFixture(props: {
	readonly itemIds: readonly string[];
	readonly openReviewContent?: BridgeWorkerReviewContentOpen;
}): Promise<HoverRuntimeFixture> {
	const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
	const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
	const pump = createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => 0 });
	const trackedContentOpen = createTrackedBridgeWorkerReviewContentOpen(
		props.openReviewContent ?? openReviewContentFromDescriptorMap,
	);
	await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
		contentItems: props.itemIds.map((itemId) => makeWorkerReviewContentMetadata({ itemId })),
		contentRequestDescriptors: props.itemIds.flatMap((itemId) => [
			makeContentRequestDescriptor({
				generation: 4,
				itemId,
				role: 'base',
				text: `${itemId} base`,
			}),
			makeContentRequestDescriptor({
				generation: 4,
				itemId,
				role: 'head',
				text: `${itemId} head`,
			}),
		]),
		createSequence: createBridgeWorkerSequenceCounter(1001),
		openReviewContent: trackedContentOpen.openContent,
		pump,
		renderSemantics: props.itemIds.map((itemId) => makeRenderSemantics({ itemId })),
		rows: props.itemIds.map((itemId, index) => ({ id: itemId, parentId: null, index })),
		schedulePreparationDrain: (drain): void => {
			scheduledDrains.push(drain);
		},
	});
	return { dispatch, postedMessages, pump, scheduledDrains, trackedContentOpen };
}

async function drainHoverRuntimeUntilQuiescent(fixture: HoverRuntimeFixture): Promise<void> {
	await drainBridgeWorkerVisibleDemandRuntimeUntilQuiescent({
		pendingContentCompletions: fixture.trackedContentOpen.pendingCompletions,
		pendingPreparationWorkIds: fixture.pump.getPendingWorkIds,
		scheduledDrains: fixture.scheduledDrains,
	});
}

function reviewRenderJobs(
	fixture: HoverRuntimeFixture,
): readonly BridgeWorkerReviewPierreRenderJobEvent['job'][] {
	return fixture.postedMessages.flatMap((postedMessage) =>
		postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message.job] : [],
	);
}

async function* emptyReviewContentFrameSequence(): AsyncIterable<never> {}
