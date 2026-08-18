import { describe, expect, test } from 'vitest';

import { createBridgeProductDeferred } from './bridge-product-async-queue.js';
import type { BridgeProductControlMux } from './bridge-product-session-authority.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataFrame,
} from './bridge-product-session-contracts.js';
import {
	BridgeProductSubscriptionState,
	type BridgeProductSubscriptionFrame,
} from './bridge-product-subscription-state.js';

const annotationInterestSha256 = 'a'.repeat(64);

describe('Bridge product subscription state', () => {
	test('captures its deferred-open epoch at admission and retains it for later frames', async () => {
		// Arrange
		const metadataReady = createBridgeProductDeferred<void>();
		const controlHarness = createAnnotationControlHarness();
		let currentReviewEpoch = 0;
		const subscriptionState = new BridgeProductSubscriptionState({
			controlMux: controlHarness.controlMux,
			createIdentifier: (): string => 'unused-annotation-update',
			ensureMetadataStream: (): Promise<void> => metadataReady.promise,
			initialOptions: {},
			onTerminal: (): void => {},
			readWorkerDerivationEpochAtAdmission: (): number => currentReviewEpoch,
			subscriptionId: 'review-annotations-admission-1',
			subscriptionKind: 'review.annotations',
		});
		const nextEvent = subscriptionState.publicSubscription.events[Symbol.asyncIterator]().next();
		subscriptionState.start();

		// Act
		currentReviewEpoch = 1;
		metadataReady.resolve();
		const open = await controlHarness.capturedOpen;
		subscriptionState.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(1),
					cursor: null,
					interestRevision: 0,
					interestSha256: annotationInterestSha256,
					kind: 'subscription.accepted',
					sourceGeneration: 0,
					subscriptionId: open.subscriptionId,
					subscriptionKind: 'review.annotations',
					subscriptionSequence: 0,
					workerDerivationEpoch: open.workerDerivationEpoch,
				}),
			),
		);
		currentReviewEpoch = 2;
		subscriptionState.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(2),
					cursor: 'review-annotations-cursor-1',
					data: {
						event: {
							eventKind: 'projection.state',
							payload: {
								commandOutcomes: [],
								expectedThreadCount: 0,
								outputHistory: [],
								recoveryStatus: 'available',
								revision: 1,
								sessions: [],
								worktreeId: '00000000-0000-7000-8000-000000000001',
							},
						},
						subscriptionKind: 'review.annotations',
					},
					interestRevision: 0,
					interestSha256: annotationInterestSha256,
					kind: 'subscription.data',
					sourceGeneration: 1,
					subscriptionId: open.subscriptionId,
					subscriptionKind: 'review.annotations',
					subscriptionSequence: 1,
					workerDerivationEpoch: open.workerDerivationEpoch,
				}),
			),
		);

		// Assert
		expect(open.workerDerivationEpoch).toBe(1);
		await expect(nextEvent).resolves.toMatchObject({
			done: false,
			value: { eventKind: 'projection.state', payload: { revision: 1 } },
		});
		subscriptionState.fail(new Error('Subscription-state test cleanup.'));
	});
});

interface CapturedAnnotationOpen {
	readonly subscriptionId: string;
	readonly workerDerivationEpoch: number;
}

function createAnnotationControlHarness(): {
	readonly capturedOpen: Promise<CapturedAnnotationOpen>;
	readonly controlMux: Pick<
		BridgeProductControlMux,
		'cancelSubscription' | 'openSubscription' | 'updateSubscriptionBatch'
	>;
} {
	let resolveCapturedOpen: ((open: CapturedAnnotationOpen) => void) | null = null;
	const capturedOpen = new Promise<CapturedAnnotationOpen>((resolve): void => {
		resolveCapturedOpen = resolve;
	});
	const controlMux: Pick<
		BridgeProductControlMux,
		'cancelSubscription' | 'openSubscription' | 'updateSubscriptionBatch'
	> = {
		cancelSubscription: async (): Promise<never> => {
			throw new Error('Annotation admission harness does not cancel subscriptions.');
		},
		openSubscription: async (props) => {
			if (props.subscription.subscriptionKind !== 'review.annotations') {
				throw new Error('Annotation admission harness accepts only Review annotations.');
			}
			resolveCapturedOpen?.(props);
			return {
				interestRevision: 0,
				interestSha256: annotationInterestSha256,
				kind: 'subscription.openAccepted',
				paneSessionId: 'pane-session-annotations',
				requestId: 'request-open-review-annotations',
				requestSequence: 2,
				subscriptionId: props.subscriptionId,
				subscriptionKind: props.subscription.subscriptionKind,
				wireVersion: 2,
				workerInstanceId: 'worker-instance-annotations',
			};
		},
		updateSubscriptionBatch: async (): Promise<never> => {
			throw new Error('Annotation admission harness does not update subscriptions.');
		},
	};
	return { capturedOpen, controlMux };
}

function metadataFrameIdentity(streamSequence: number): {
	readonly metadataStreamId: string;
	readonly paneSessionId: string;
	readonly streamSequence: number;
	readonly wireVersion: 2;
	readonly workerInstanceId: string;
} {
	return {
		metadataStreamId: 'metadata-stream-annotations',
		paneSessionId: 'pane-session-annotations',
		streamSequence,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-annotations',
	};
}

function requireSubscriptionFrame(
	frame: BridgeProductMetadataFrame,
): BridgeProductSubscriptionFrame {
	switch (frame.kind) {
		case 'subscription.accepted':
		case 'subscription.cancelled':
		case 'subscription.data':
		case 'subscription.end':
		case 'subscription.interestsCommitted':
		case 'subscription.reset':
			return frame;
		case 'content.cancelled':
		case 'metadataStream.accepted':
		case 'metadataStream.error':
		case 'pane.presentation':
		case 'pane.surfaceSelectionRequested':
			throw new Error(`Expected a subscription frame, received ${frame.kind}.`);
	}
}
