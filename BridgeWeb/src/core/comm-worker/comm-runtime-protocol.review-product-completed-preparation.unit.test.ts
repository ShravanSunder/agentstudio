import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import { reviewSnapshotWithContentEvent } from './bridge-comm-worker-runtime-protocol.review-product-fixtures.test-support.js';
import {
	makeReviewPanePresentationFrame,
	requirePanePresentationSink,
} from './bridge-comm-worker-runtime-protocol.review-product-pane-presentation.test-support.js';
import { drainBridgeCommWorkerPreparationUntilIdle } from './bridge-comm-worker-runtime-protocol.review-product-preparation.test-support.js';
import { makeReviewProductTransport } from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

describe('Bridge comm worker completed Review preparation lifecycle', () => {
	test('does not replay completed Review preparation or reset when native foreground returns to File', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const openedDescriptorIds: string[] = [];
		let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-completed-foreground-return',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			openReviewContent: (descriptor) => {
				openedDescriptorIds.push(descriptor.descriptorId);
				return makeImmediateReviewContentStream(descriptor, 'hello world\n');
			},
			productTransport: makeReviewProductTransport({
				onPanePresentationSink: (sink): void => {
					panePresentationSink = sink;
				},
				reviewSubscription,
				subscribedKinds: [],
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		await drainBridgeCommWorkerPreparationUntilIdle(
			scheduledDrains,
			flushBridgeWorkerRuntimeContinuations,
		);
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 1,
				requestId: 'request-review-mode-before-completed-preparation',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 1,
					sessionId: 'review-completed-foreground-return-session',
				},
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 2,
				requestId: 'request-review-completed-foreground-return-selection',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 3,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'request-review-completed-foreground-return-viewport',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await drainBridgeCommWorkerPreparationUntilIdle(
			scheduledDrains,
			flushBridgeWorkerRuntimeContinuations,
		);
		const completedOpenCount = openedDescriptorIds.length;
		expect(completedOpenCount).toBeGreaterThan(0);

		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 4,
				requestId: 'request-file-mode-before-review-foreground-return',
				update: {
					activeSource: null,
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 2,
					sessionId: 'review-completed-foreground-return-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const messageCountBeforeNativeCycle = postedMessages.length;
		requirePanePresentationSink(panePresentationSink)(
			makeReviewPanePresentationFrame(2, 'loadedHidden'),
		);
		requirePanePresentationSink(panePresentationSink)(
			makeReviewPanePresentationFrame(3, 'foreground'),
		);
		await drainBridgeCommWorkerPreparationUntilIdle(
			scheduledDrains,
			flushBridgeWorkerRuntimeContinuations,
		);

		expect(openedDescriptorIds).toHaveLength(completedOpenCount);
		expect(
			postedMessages
				.slice(messageCountBeforeNativeCycle)
				.map(({ message }) => message)
				.filter(
					(message) =>
						message.kind === 'reviewPierreRenderJob' ||
						(message.kind === 'reviewRenderPatch' &&
							message.patches.some((patch): boolean => patch.slice !== 'panelChrome')),
				),
		).toEqual([]);
	});
});
