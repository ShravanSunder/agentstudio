import { describe, expect, test, vi } from 'vitest';

import { createBridgeProductDeferred } from './bridge-product-async-queue.js';
import type { BridgeProductMetadataApplicationOpen } from './bridge-product-metadata-application-protocol.js';
import {
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
	bridgeProductReviewMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataFrame,
} from './bridge-product-session-contracts.js';
import {
	BridgeProductSubscriptionEpochRetiredError,
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
			// Native moved the surface past this admission: a retirement, not a failure.
			await expect(terminal).rejects.toMatchObject({
				name: 'BridgeProductSubscriptionEpochRetiredError',
				nextWorkerDerivationEpoch: 1,
				surface: 'review',
			});
		} finally {
			state.fail(new Error('Epoch reconciliation test cleanup.'));
		}
	});

	test('fails a subscription native reports missing at its own epoch', async () => {
		// Arrange
		const harness = createAnnotationControlHarness();
		const terminalErrors: unknown[] = [];
		const state = new BridgeProductSubscriptionState({
			controlMux: harness.controlMux,
			createIdentifier: (): string => 'unused-missing-reconciliation-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (_subscriptionId, error): void => {
				terminalErrors.push(error);
			},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 1,
			subscriptionId: 'missing-annotation-subscription',
		});
		state.start();
		await harness.capturedOpen;
		await state.update({});
		const terminal = state.publicSubscription.events[Symbol.asyncIterator]().next();
		void terminal.catch((): void => {});

		// Act
		await state.applyReconciliation({
			disposition: 'reopenRequired',
			reason: 'native_missing',
			requiredWorkerDerivationEpoch: 1,
			subscriptionId: 'missing-annotation-subscription',
			subscriptionKind: 'review.annotations',
		});

		// Assert: no newer epoch was involved, so the consumer sees a reset.
		await expect(terminal).rejects.toBeInstanceOf(BridgeProductSubscriptionResetError);
		expect(terminalErrors).toHaveLength(1);
	});

	test('retires an unreleased subscription when native ends it for a newer surface epoch', async () => {
		// Arrange: the worker already serves epoch 2; native's floor retired the
		// epoch-1 subscription before the worker released it.
		const harness = createAnnotationControlHarness();
		let surfaceEpoch = 1;
		const terminalErrors: unknown[] = [];
		const state = new BridgeProductSubscriptionState({
			controlMux: harness.controlMux,
			createIdentifier: (): string => 'unused-floor-retired-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (_subscriptionId, error, drainUntilNativeTerminal): void => {
				terminalErrors.push({ drainUntilNativeTerminal, error });
			},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => surfaceEpoch,
			subscriptionId: 'floor-retired-subscription',
		});
		state.start();
		const open = await harness.capturedOpen;
		await state.update({});
		const terminal = state.publicSubscription.events[Symbol.asyncIterator]().next();
		void terminal.catch((): void => {});
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
		surfaceEpoch = 2;

		// Act
		state.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(2),
					...correlation,
					kind: 'subscription.reset',
					reason: 'epoch_retired',
					subscriptionSequence: 1,
				}),
			),
		);

		// Assert: a clean native terminal that the consumer reads as a retirement.
		await expect(terminal).rejects.toMatchObject({
			name: 'BridgeProductSubscriptionEpochRetiredError',
			nextWorkerDerivationEpoch: 2,
		});
		expect(terminalErrors).toEqual([{ drainUntilNativeTerminal: undefined, error: undefined }]);
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
		{ cancelTiming: 'after the failed open settles' },
		{ cancelTiming: 'while the failing open is in flight' },
	] as const)(
		'settles cancellation of a subscription whose open was refused $cancelTiming',
		async ({ cancelTiming }) => {
			// Arrange: native refuses the open, as when the worktree annotation source
			// is unavailable. The subscription becomes terminal through its open failure.
			const openRefusal = new Error('Annotation source is unavailable.');
			const openResponse = createBridgeProductDeferred<never>();
			let cancelControlCount = 0;
			const terminalErrors: unknown[] = [];
			const state = new BridgeProductSubscriptionState({
				controlMux: {
					cancelSubscription: async (): Promise<void> => {
						cancelControlCount += 1;
					},
					openSubscription: (): Promise<never> => openResponse.promise,
					updateSubscriptionBatch: async (): Promise<never> => {
						throw new Error('Refused-open test does not update subscriptions.');
					},
				},
				createIdentifier: (): string => 'unused-refused-open-update',
				ensureMetadataStream: async (): Promise<void> => {},
				initialOptions: {},
				onTerminal: (_subscriptionId, error): void => {
					terminalErrors.push(error);
				},
				protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
				readWorkerDerivationEpochAtAdmission: (): number => 0,
				subscriptionId: 'refused-open-subscription',
			});
			const terminalEvent = state.publicSubscription.events[Symbol.asyncIterator]().next();
			void terminalEvent.catch((): void => {});
			state.start();

			// Act
			let cancellation: Promise<void>;
			if (cancelTiming === 'while the failing open is in flight') {
				cancellation = state.cancel();
				openResponse.reject(openRefusal);
			} else {
				openResponse.reject(openRefusal);
				await expect(terminalEvent).rejects.toBe(openRefusal);
				cancellation = state.cancel();
			}

			// Assert: retiring an already-terminal subscription is a local no-op, so a
			// surface epoch change waiting on it can proceed to open its successor.
			await expect(cancellation).resolves.toBeUndefined();
			await expect(terminalEvent).rejects.toBe(openRefusal);
			expect(cancelControlCount).toBe(0);
			expect(terminalErrors).toEqual([openRefusal]);
		},
	);

	test('still rejects cancellation when native refuses to cancel an active subscription', async () => {
		// Arrange
		const harness = createAnnotationControlHarness();
		const state = new BridgeProductSubscriptionState({
			controlMux: harness.controlMux,
			createIdentifier: (): string => 'unused-active-cancel-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (): void => {},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 0,
			subscriptionId: 'active-cancel-refusal-subscription',
		});
		state.start();
		await harness.capturedOpen;
		await state.update({});

		// Act
		const cancellation = state.cancel();

		// Assert: the settle-after-failure rule must not hide a live control failure.
		await expect(cancellation).rejects.toThrow(
			'Annotation admission harness does not cancel subscriptions.',
		);
	});

	test('drains a subscription whose stale cancel native refused until native retires it for the new epoch', async () => {
		// Arrange: native's surface floor already advanced, so it refuses the epoch-1
		// cancel and ends the subscription itself with an epoch_retired reset.
		const harness = createAnnotationControlHarness();
		const terminalErrors: unknown[] = [];
		const state = new BridgeProductSubscriptionState({
			controlMux: {
				...harness.controlMux,
				cancelSubscription: async (): Promise<never> => {
					throw new BridgeProductControlRequestError({
						code: 'resync_required',
						message: 'Stale worker derivation epoch.',
						retryAfterMilliseconds: null,
						retryable: true,
					});
				},
			},
			createIdentifier: (): string => 'unused-stale-cancel-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (_subscriptionId, error): void => {
				terminalErrors.push(error);
			},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 1,
			subscriptionId: 'stale-cancel-subscription',
		});
		state.start();
		const open = await harness.capturedOpen;
		await state.update({});
		const correlation = {
			cursor: null,
			interestRevision: 0,
			interestSha256: annotationInterestSha256,
			sourceGeneration: 0,
			subscriptionId: open.subscriptionId,
			subscriptionKind: 'review.annotations',
			workerDerivationEpoch: open.workerDerivationEpoch,
		};

		// Act
		await state.cancel();
		const lateFrame = (): void => {
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
		};

		// Assert: frames native queued before its terminal drain instead of poisoning
		// the shared stream, and the epoch_retired reset ends the subscription cleanly.
		expect(lateFrame).not.toThrow();
		expect(terminalErrors).toEqual([]);
		state.acceptFrame(
			requireSubscriptionFrame(
				bridgeProductMetadataFrameSchema.parse({
					...metadataFrameIdentity(2),
					...correlation,
					kind: 'subscription.reset',
					reason: 'epoch_retired',
					subscriptionSequence: 1,
				}),
			),
		);
		expect(terminalErrors).toEqual([undefined]);
	});

	test('releases an admitted subscription at its own epoch before a surface advance and leaves an unadmitted one alone', async () => {
		// Arrange
		const cancelledEpochs: number[] = [];
		const harness = createAnnotationControlHarness();
		const controlMux = {
			...harness.controlMux,
			cancelSubscription: async (props: {
				readonly workerDerivationEpoch: number;
			}): Promise<void> => {
				cancelledEpochs.push(props.workerDerivationEpoch);
			},
		};
		const admitted = new BridgeProductSubscriptionState({
			controlMux,
			createIdentifier: (): string => 'unused-admitted-retire-update',
			ensureMetadataStream: async (): Promise<void> => {},
			initialOptions: {},
			onTerminal: (): void => {},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 1,
			subscriptionId: 'admitted-retire-subscription',
		});
		admitted.start();
		await harness.capturedOpen;
		await admitted.update({});
		const unadmitted = new BridgeProductSubscriptionState({
			controlMux,
			createIdentifier: (): string => 'unused-unadmitted-retire-update',
			ensureMetadataStream: (): Promise<void> => new Promise<void>((): void => {}),
			initialOptions: {},
			onTerminal: (): void => {},
			protocol: bridgeProductReviewAnnotationMetadataApplicationProtocol,
			readWorkerDerivationEpochAtAdmission: (): number => 2,
			subscriptionId: 'unadmitted-retire-subscription',
		});
		unadmitted.start();
		const retirement = new BridgeProductSubscriptionEpochRetiredError({
			nextWorkerDerivationEpoch: 2,
			surface: 'review',
		});
		const admittedEvent = admitted.publicSubscription.events[Symbol.asyncIterator]().next();

		try {
			// Act
			await Promise.all([
				admitted.retireBeforeWorkerDerivationEpochAdvance(retirement),
				unadmitted.retireBeforeWorkerDerivationEpochAdvance(retirement),
			]);

			// Assert: one cancel, tagged with the epoch native admitted it at, and the
			// consumer learns it was retired rather than failed.
			expect(cancelledEpochs).toEqual([1]);
			await expect(admittedEvent).rejects.toBe(retirement);
		} finally {
			admitted.fail(new Error('Retirement test cleanup.'));
			unadmitted.fail(new Error('Retirement test cleanup.'));
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
