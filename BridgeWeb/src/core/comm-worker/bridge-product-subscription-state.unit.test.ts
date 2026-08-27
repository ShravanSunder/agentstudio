import { describe, expect, test } from 'vitest';

import { createBridgeProductDeferred } from './bridge-product-async-queue.js';
import type { BridgeProductMetadataApplicationOpen } from './bridge-product-metadata-application-protocol.js';
import { bridgeProductReviewAnnotationMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataFrame,
} from './bridge-product-session-contracts.js';
import {
	BridgeProductSubscriptionState,
	type BridgeProductSubscriptionFrame,
	type BridgeProductSubscriptionStateControlMux,
} from './bridge-product-subscription-state.js';

type ReviewAnnotationOpen = BridgeProductMetadataApplicationOpen<
	typeof bridgeProductReviewAnnotationMetadataApplicationProtocol
>;

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
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
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
		const catalogBeginEvent = {
			authority: {
				applicationSourceGeneration: 1,
				worktreeId: 'worktree-1',
			},
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: 1,
				expectedEntryCount: 0,
				kind: 'catalog.begin',
				transferId: 'annotation-catalog-transfer-1',
			},
		} as const;
		subscriptionState.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(2),
					cursor: 'review-annotations-cursor-1',
					data: {
						event: catalogBeginEvent,
						subscriptionKind: 'review.annotations',
					},
					interestRevision: 0,
					interestSha256: annotationInterestSha256,
					kind: 'subscription.data',

					operationCorrelationId: null,
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
		await expect(nextEvent).resolves.toEqual({
			done: false,
			value: {
				data: catalogBeginEvent,
				metadataStreamId: 'metadata-stream-annotations',
				operationCorrelationId: null,
				sourceGeneration: 1,
				streamSequence: 2,
				subscriptionId: open.subscriptionId,
				subscriptionKind: 'review.annotations',
				subscriptionSequence: 1,
				workerDerivationEpoch: open.workerDerivationEpoch,
			},
		});
		subscriptionState.fail(new Error('Subscription-state test cleanup.'));
	});

	test('rejects cross-kind and generation-mismatched raw data after generic barriers', async () => {
		for (const testCase of [
			{
				data: {
					event: {
						authority: {
							applicationSourceGeneration: 2,
							worktreeId: 'worktree-1',
						},
						kind: 'annotation.controlChanged',
						reason: 'discovery',
					},
					subscriptionKind: 'file.annotations',
				},
				expectedError: /subscriptionKind|literal/iu,
				frameSourceGeneration: 2,
			},
			{
				data: {
					event: {
						authority: {
							applicationSourceGeneration: 3,
							worktreeId: 'worktree-1',
						},
						kind: 'annotation.sessionChanged',
						semanticRevision: 4,
						sessionId: '00000000-0000-7000-8000-000000000001',
					},
					subscriptionKind: 'review.annotations',
				},
				expectedError: /generation/iu,
				frameSourceGeneration: 2,
			},
		]) {
			const controlHarness = createAnnotationControlHarness();
			const subscriptionState = new BridgeProductSubscriptionState({
				controlMux: controlHarness.controlMux,
				createIdentifier: (): string => 'unused-annotation-update',
				ensureMetadataStream: async (): Promise<void> => {},
				initialOptions: {},
				onTerminal: (): void => {},
				protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
				readWorkerDerivationEpochAtAdmission: (): number => 1,
				subscriptionId: 'review-annotations-validation-1',
			});
			subscriptionState.start();
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

			expect(() =>
				subscriptionState.acceptFrame(
					requireSubscriptionFrame(
						bridgeProductMetadataFrameSchema.parse({
							...metadataFrameIdentity(2),
							cursor: null,
							data: testCase.data,
							interestRevision: 0,
							interestSha256: annotationInterestSha256,
							kind: 'subscription.data',
							operationCorrelationId: null,
							sourceGeneration: testCase.frameSourceGeneration,
							subscriptionId: open.subscriptionId,
							subscriptionKind: 'review.annotations',
							subscriptionSequence: 1,
							workerDerivationEpoch: open.workerDerivationEpoch,
						}),
					),
				),
			).toThrow(testCase.expectedError);
			subscriptionState.fail(new Error('Subscription validation test cleanup.'));
		}
	});
});

interface CapturedAnnotationOpen {
	readonly subscriptionId: string;
	readonly workerDerivationEpoch: number;
}

function createAnnotationControlHarness(): {
	readonly capturedOpen: Promise<CapturedAnnotationOpen>;
	readonly controlMux: BridgeProductSubscriptionStateControlMux<
		'review.annotations',
		ReviewAnnotationOpen,
		{ readonly subscriptionKind: 'review.annotations' }
	>;
} {
	let resolveCapturedOpen: ((open: CapturedAnnotationOpen) => void) | null = null;
	const capturedOpen = new Promise<CapturedAnnotationOpen>((resolve): void => {
		resolveCapturedOpen = resolve;
	});
	const controlMux: BridgeProductSubscriptionStateControlMux<
		'review.annotations',
		ReviewAnnotationOpen,
		{ readonly subscriptionKind: 'review.annotations' }
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
	throw new Error('Unsupported Bridge product metadata frame.');
}
