import { describe, expect, test, vi } from 'vitest';

import { createBridgeProductDeferred } from './bridge-product-async-queue.js';
import type { BridgeProductMetadataApplicationOpen } from './bridge-product-metadata-application-protocol.js';
import {
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
	bridgeProductReviewMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataFrame,
} from './bridge-product-session-contracts.js';
import {
	BridgeProductSubscriptionState,
	BridgeProductSubscriptionResetError,
	type BridgeProductSubscriptionFrame,
	type BridgeProductSubscriptionStateControlMux,
} from './bridge-product-subscription-state.js';
import {
	emptyInterestHash,
	waitForCondition,
} from './test-fixtures/bridge-product-transport-metadata.test-support.js';

type ReviewAnnotationOpen = BridgeProductMetadataApplicationOpen<
	typeof bridgeProductReviewAnnotationMetadataApplicationProtocol
>;

const annotationInterestSha256 = 'a'.repeat(64);

describe('Bridge product subscription state', () => {
	test('reconciles an older subscription against the current surface epoch without retagging its admission', async () => {
		// Arrange: an annotation subscription opens before its surface metadata
		// advances the shared epoch, as in the real four-subscription startup.
		const harness = createAnnotationControlHarness();
		let surfaceEpoch = 0;
		const state = new BridgeProductSubscriptionState({
			controlMux: harness.controlMux,
			createIdentifier: (): string => 'unused-epoch-reconciliation-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (): void => {},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => surfaceEpoch,
			subscriptionId: 'older-annotation-subscription',
		});
		state.start();
		const admittedOpen = await harness.capturedOpen;
		await state.update({});

		try {
			// Act: reconciliation asks native whether this ID can serve the current
			// epoch. Native, not the worker, decides whether a fresh ID is required.
			surfaceEpoch = 1;
			const claim = state.reconciliationClaim();

			// Assert
			expect(admittedOpen.workerDerivationEpoch).toBe(0);
			expect(claim).toMatchObject({
				subscriptionId: 'older-annotation-subscription',
				workerDerivationEpoch: 1,
			});
			const terminal = state.publicSubscription.events[Symbol.asyncIterator]().next();
			void terminal.catch((): void => {});
			await state.applyReconciliation({
				disposition: 'reopenRequired',
				reason: 'epoch_advanced',
				requiredWorkerDerivationEpoch: 1,
				subscriptionId: 'older-annotation-subscription',
				subscriptionKind: 'review.annotations',
			});
			await expect(terminal).rejects.toBeInstanceOf(BridgeProductSubscriptionResetError);
		} finally {
			state.fail(new Error('Epoch reconciliation test cleanup.'));
		}
	});

	test('rechecks recovery admission after asynchronous interest hashing', async () => {
		// Arrange
		const digestStarted = createBridgeProductDeferred<void>();
		const digestResult = createBridgeProductDeferred<ArrayBuffer>();
		const controlResponse = createBridgeProductDeferred<void>();
		let updateControlCount = 0;
		const state = new BridgeProductSubscriptionState({
			controlMux: {
				cancelSubscription: async (): Promise<void> => {},
				openSubscription: async (): Promise<{
					readonly interestRevision: number;
					readonly interestSha256: string;
				}> => ({
					interestRevision: 0,
					interestSha256: emptyInterestHash('review.metadata'),
				}),
				updateSubscriptionBatch: (): Promise<void> => {
					updateControlCount += 1;
					return controlResponse.promise;
				},
			},
			createIdentifier: (): string => 'recovery-hash-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: { interests: [] },
			onTerminal: (): void => {},
			protocol: bridgeProductReviewMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 0,
			subscriptionId: 'recovery-hash-subscription',
		});
		state.start();
		await state.update({ interests: [] });
		const digestSpy = vi.spyOn(globalThis.crypto.subtle, 'digest').mockImplementationOnce(() => {
			digestStarted.resolve();
			return digestResult.promise;
		});
		const update = state.update({ interests: [{ itemIds: ['item-1'], lane: 'foreground' }] });
		void update.catch((): void => {});
		await digestStarted.promise;

		try {
			// Act: recovery starts while preparation is suspended, before control admission.
			state.beginRecovery();
			digestResult.resolve(new Uint8Array(32).buffer);
			await new Promise<void>((resolve): void => {
				setImmediate(resolve);
			});

			// Assert: completing preparation is not permission to bypass the recovery gate.
			expect(updateControlCount).toBe(0);
		} finally {
			await state.finishRecovery();
			await waitForCondition(() => updateControlCount === 1);
			state.fail(new Error('Interest-hash test cleanup.'));
			controlResponse.resolve();
			await update.catch((): void => {});
			digestSpy.mockRestore();
		}
	});

	test('does not start a queued operation across a newly installed recovery gate', async () => {
		// Arrange: let the operation enter its queue callback, then begin recovery
		// before any extra asynchronous admission hop can start the control call.
		const harness = createAnnotationControlHarness();
		let cancelControlCount = 0;
		const state = new BridgeProductSubscriptionState({
			controlMux: {
				...harness.controlMux,
				cancelSubscription: async (): Promise<void> => {
					cancelControlCount += 1;
				},
			},
			createIdentifier: (): string => 'unused-recovery-gate-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (): void => {},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 1,
			subscriptionId: 'recovery-gate-subscription',
		});
		state.start();
		await harness.capturedOpen;
		await state.update({});
		const cancellation = state.cancel();
		void cancellation.catch((): void => {});
		await Promise.resolve();
		const admittedBeforeRecovery = cancelControlCount;

		try {
			// Act
			state.beginRecovery();
			await Promise.resolve();

			// Assert: controls already started are allowed to settle, but a queued
			// control cannot newly start while the recovery gate is closed.
			expect(cancelControlCount).toBe(admittedBeforeRecovery);
		} finally {
			state.fail(new Error('Recovery-gate test cleanup.'));
			await cancellation.catch((): void => {});
		}
	});

	test.each([
		'interest_mismatch',
		'producer_overflow',
		'sequence_gap',
		'stale_source',
		'snapshot_required',
	] as const)('preserves the generic %s reset reason as a terminal typed error', async (reason) => {
		// Arrange
		const controlHarness = createAnnotationControlHarness();
		let terminalCount = 0;
		const state = new BridgeProductSubscriptionState({
			controlMux: controlHarness.controlMux,
			createIdentifier: (): string => 'unused-reset-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (): void => {
				terminalCount += 1;
			},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 1,
			subscriptionId: 'reset-reason-subscription',
		});
		state.start();
		const open = await controlHarness.capturedOpen;
		const correlation = {
			cursor: null,
			interestRevision: 0,
			interestSha256: annotationInterestSha256,
			sourceGeneration: 0,
			subscriptionId: open.subscriptionId,
			subscriptionKind: 'review.annotations',
			workerDerivationEpoch: open.workerDerivationEpoch,
		};
		state.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(1),
					...correlation,
					kind: 'subscription.accepted',
					subscriptionSequence: 0,
				}),
			),
		);
		const nextEvent = state.publicSubscription.events[Symbol.asyncIterator]().next();

		// Act
		state.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(2),
					...correlation,
					kind: 'subscription.reset',
					reason,
					subscriptionSequence: 1,
				}),
			),
		);

		// Assert
		await expect(nextEvent).rejects.toBeInstanceOf(BridgeProductSubscriptionResetError);
		await expect(nextEvent).rejects.toMatchObject({ reason });
		state.fail(new Error('Already-terminal reset cleanup.'));
		expect(terminalCount).toBe(1);
	});

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
