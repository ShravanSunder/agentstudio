import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
	type BridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type {
	BridgeProductResetReason,
	BridgeProductSurface,
} from './bridge-product-contract-primitives.js';
import type {
	BridgeProductMetadataApplicationProtocol,
	BridgeProductMetadataDataFrame,
} from './bridge-product-metadata-application-protocol.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import type {
	BridgeProductControlRequest,
	BridgeProductMetadataFrame,
	BridgeProductResyncReconciliationOutcome,
} from './bridge-product-session-contracts.js';
import { BridgeProductSubscriptionFrameFailure } from './bridge-product-subscription-frame-failure.js';

export class BridgeProductSubscriptionResetError extends Error {
	readonly reason: BridgeProductResetReason;

	constructor(reason: BridgeProductResetReason) {
		super(`Bridge product subscription reset: ${reason}.`);
		this.name = 'BridgeProductSubscriptionResetError';
		this.reason = reason;
	}
}

/**
 * Terminal for a subscription retired because its surface advanced to a newer
 * worker derivation epoch. Consumers that still need the data reopen; the
 * replacement admits at the new epoch.
 */
export class BridgeProductSubscriptionEpochRetiredError extends Error {
	readonly nextWorkerDerivationEpoch: number;
	readonly surface: BridgeProductSurface;

	constructor(props: {
		readonly nextWorkerDerivationEpoch: number;
		readonly surface: BridgeProductSurface;
	}) {
		super(
			`Bridge product ${props.surface} subscription retired for worker epoch ${props.nextWorkerDerivationEpoch}.`,
		);
		this.name = 'BridgeProductSubscriptionEpochRetiredError';
		this.nextWorkerDerivationEpoch = props.nextWorkerDerivationEpoch;
		this.surface = props.surface;
	}
}

export type BridgeProductSubscriptionIdentifierPurpose = 'subscription-update';

export type BridgeProductSubscriptionFrame = Exclude<
	BridgeProductMetadataFrame,
	| { readonly kind: 'content.cancelled' }
	| { readonly kind: 'metadataStream.accepted' }
	| { readonly kind: 'metadataStream.error' }
	| { readonly kind: 'pane.presentation' }
	| { readonly kind: 'pane.surfaceSelectionRequested' }
	| { readonly kind: 'subscription.batchBegin' }
	| { readonly kind: 'subscription.batchPart' }
	| { readonly kind: 'subscription.batchComplete' }
>;

export interface BridgeProductSubscriptionFrameSink {
	readonly subscriptionId: string;
	readonly surface: BridgeProductSurface;
	retireBeforeWorkerDerivationEpochAdvance(
		retirement: BridgeProductSubscriptionEpochRetiredError,
	): Promise<void>;
	acceptFrame(frame: BridgeProductSubscriptionFrame): void;
	fail(error: unknown): void;
	reconciliationClaim():
		| Extract<
				BridgeProductControlRequest,
				{ kind: 'workerSession.resync' }
		  >['activeSubscriptions'][number]
		| null;
	applyReconciliation(outcome: BridgeProductResyncReconciliationOutcome): Promise<void>;
	beginRecovery(): void;
	finishRecovery(): Promise<void>;
}

export interface BridgeProductSubscriptionStateControlMux<
	TKind extends string,
	TOpen extends { readonly subscriptionKind: TKind },
	TInterestDelta extends { readonly subscriptionKind: TKind },
> {
	cancelSubscription(props: {
		readonly subscriptionId: string;
		readonly subscriptionKind: TKind;
		readonly workerDerivationEpoch: number;
	}): Promise<unknown>;
	openSubscription(props: {
		readonly subscription: TOpen;
		readonly subscriptionId: string;
		readonly workerDerivationEpoch: number;
	}): Promise<{ readonly interestRevision: number; readonly interestSha256: string }>;
	updateSubscriptionBatch(props: {
		readonly baseInterestRevision: number;
		readonly baseInterestSha256: string;
		readonly batchCount: number;
		readonly batchIndex: number;
		readonly delta: TInterestDelta;
		readonly subscriptionId: string;
		readonly targetInterestRevision: number;
		readonly targetInterestSha256: string;
		readonly totalDeltaItemCount: number;
		readonly updateId: string;
		readonly workerDerivationEpoch: number;
	}): Promise<unknown>;
}

export interface BridgeProductSubscriptionStateProps<
	TKind extends string,
	TOptions,
	TUpdateOptions,
	TOpen extends { readonly subscriptionKind: TKind },
	TInterestState extends { readonly subscriptionKind: TKind },
	TInterestDelta extends { readonly subscriptionKind: TKind },
	TData extends { readonly event: unknown; readonly subscriptionKind: TKind },
> {
	readonly controlMux: BridgeProductSubscriptionStateControlMux<TKind, TOpen, TInterestDelta>;
	readonly createIdentifier: (purpose: BridgeProductSubscriptionIdentifierPurpose) => string;
	readonly ensureMetadataStream: () => Promise<void>;
	readonly initialOptions: TOptions;
	/**
	 * `drainUntilNativeTerminal` is true when native may still send frames for this
	 * id: it was admitted and native has not ended it. The owner must keep routing
	 * those frames to a drain rather than treating them as unknown.
	 */
	readonly onTerminal: (
		subscriptionId: string,
		error?: unknown,
		drainUntilNativeTerminal?: boolean,
	) => void;
	readonly protocol: BridgeProductMetadataApplicationProtocol<
		TKind,
		TOptions,
		TUpdateOptions,
		TOpen,
		TInterestState,
		TInterestDelta,
		TData
	>;
	readonly readWorkerDerivationEpochAtAdmission: () => number;
	/**
	 * Waits while the surface retires older-epoch subscriptions, then runs `admit`
	 * with the surface epoch in the same synchronous turn as the final gate check,
	 * so no advance can slip between the check and the admitted request.
	 */
	readonly admitAtWorkerDerivationEpoch?: <TAdmission>(
		admit: (workerDerivationEpoch: number) => TAdmission,
	) => Promise<TAdmission>;
	readonly subscriptionId: string;
}

export class BridgeProductSubscriptionState<
	TKind extends string,
	TOptions,
	TUpdateOptions,
	TOpen extends { readonly subscriptionKind: TKind },
	TInterestState extends { readonly subscriptionKind: TKind },
	TInterestDelta extends { readonly subscriptionKind: TKind },
	TData extends { readonly event: unknown; readonly subscriptionKind: TKind },
> implements BridgeProductSubscriptionFrameSink {
	#accepted = false;
	/**
	 * Set once a release (consumer cancel or epoch retirement) is requested. From then
	 * on nothing waits on this subscription's frames, no interests are sent, and
	 * native's remaining frames drain silently until its terminal.
	 */
	#released = false;
	/** Why the release was requested; operations it cut short settle with this. */
	#releaseReason: Error | null = null;
	#releaseOperation: Promise<void> | null = null;
	/** Native ended this subscription (terminal frame or reconciliation). */
	#nativeTerminalObserved = false;
	/** Native refused the open, so it never held this subscription. */
	#openRefusedByNative = false;
	/** Native accepted the open control, so a release must cancel it. */
	#openAcknowledged = false;
	readonly #admitAtWorkerDerivationEpoch: <TAdmission>(
		admit: (workerDerivationEpoch: number) => TAdmission,
	) => Promise<TAdmission>;
	readonly #controlMux: BridgeProductSubscriptionStateProps<
		TKind,
		TOptions,
		TUpdateOptions,
		TOpen,
		TInterestState,
		TInterestDelta,
		TData
	>['controlMux'];
	readonly #createIdentifier: (purpose: BridgeProductSubscriptionIdentifierPurpose) => string;
	#currentInterestHash: string | null = null;
	#currentInterestRevision = 0;
	#currentInterestState: TInterestState;
	readonly #ensureMetadataStream: () => Promise<void>;
	readonly #eventQueue = new BridgeProductBoundedAsyncQueue<
		BridgeProductMetadataDataFrame<TData['event']>
	>(64);
	#expectedSubscriptionSequence = 0;
	readonly #initialOptions: TOptions;
	readonly #onTerminal: BridgeProductSubscriptionStateProps<
		TKind,
		TOptions,
		TUpdateOptions,
		TOpen,
		TInterestState,
		TInterestDelta,
		TData
	>['onTerminal'];
	#operation: Promise<void> = Promise.resolve();
	#pendingBarrier: PendingSubscriptionBarrier<TInterestState> | null = null;
	#recoveryGate: BridgeProductDeferred<void> | null = null;
	#resetReplay: ResetReplay<TInterestState> | null = null;
	readonly #protocol: BridgeProductMetadataApplicationProtocol<
		TKind,
		TOptions,
		TUpdateOptions,
		TOpen,
		TInterestState,
		TInterestDelta,
		TData
	>;
	readonly #readWorkerDerivationEpochAtAdmission: () => number;
	readonly subscriptionId: string;
	#terminal = false;
	#admittedWorkerDerivationEpoch: number | null = null;

	constructor(
		props: BridgeProductSubscriptionStateProps<
			TKind,
			TOptions,
			TUpdateOptions,
			TOpen,
			TInterestState,
			TInterestDelta,
			TData
		>,
	) {
		this.#controlMux = props.controlMux;
		this.#createIdentifier = props.createIdentifier;
		this.#ensureMetadataStream = props.ensureMetadataStream;
		this.#initialOptions = props.initialOptions;
		this.#onTerminal = props.onTerminal;
		this.#protocol = props.protocol;
		this.#readWorkerDerivationEpochAtAdmission = props.readWorkerDerivationEpochAtAdmission;
		this.#admitAtWorkerDerivationEpoch =
			props.admitAtWorkerDerivationEpoch ??
			(async <TAdmission>(
				admit: (workerDerivationEpoch: number) => TAdmission,
			): Promise<TAdmission> => admit(props.readWorkerDerivationEpochAtAdmission()));
		this.subscriptionId = props.subscriptionId;
		this.#currentInterestState = props.protocol.interestStateSchema.parse(
			props.protocol.emptyInterestState(),
		);
	}

	get publicSubscription(): {
		readonly events: AsyncIterable<BridgeProductMetadataDataFrame<TData['event']>>;
		readonly subscriptionId: string;
		readonly subscriptionKind: TKind;
		cancel(): Promise<void>;
		update(options: TUpdateOptions): Promise<void>;
	} {
		return {
			cancel: (): Promise<void> => this.cancel(),
			events: this.#eventQueue,
			subscriptionId: this.subscriptionId,
			subscriptionKind: this.#protocol.kind,
			update: (options): Promise<void> => this.update(options),
		};
	}

	start(): void {
		this.#operation = this.#initialize().catch((error: unknown): never => {
			this.fail(error);
			throw error;
		});
		void this.#operation.catch((): void => {});
	}

	get surface(): BridgeProductSurface {
		return this.#protocol.surface;
	}

	/**
	 * Releases this subscription before its surface advances past its admitted
	 * epoch. Native refuses controls tagged with a stale epoch, so the cancel must
	 * be acknowledged first. The consumer learns of the retirement at once; an
	 * operation waiting on one of this subscription's frames settles with it rather
	 * than holding the advance. A subscription not yet admitted is left alone: it
	 * admits at the new epoch. One already releasing settles with that release.
	 */
	retireBeforeWorkerDerivationEpochAdvance(
		retirement: BridgeProductSubscriptionEpochRetiredError,
	): Promise<void> {
		const admittedEpoch = this.#admittedWorkerDerivationEpoch;
		if (
			this.#terminal ||
			admittedEpoch === null ||
			admittedEpoch >= retirement.nextWorkerDerivationEpoch
		) {
			return Promise.resolve();
		}
		const consumerRelease = this.#releaseOperation;
		this.#markReleased(retirement);
		this.#rejectFrameWaiters(retirement);
		if (consumerRelease === null) this.#eventQueue.fail(retirement, true);
		return (consumerRelease ?? this.#queueRelease(retirement)).catch((): void => {});
	}

	update(options: TUpdateOptions): Promise<void> {
		return this.#enqueue(() => this.#updateTo(options));
	}

	/**
	 * Releases after the operations queued before it, then resolves once native
	 * acknowledges the cancel. Frames native already queued drain silently until
	 * its terminal; nothing here waits on them.
	 */
	cancel(): Promise<void> {
		return (
			this.#releaseOperation ??
			this.#queueRelease(new Error('Bridge product subscription was cancelled.'))
		);
	}

	acceptFrame(frame: BridgeProductSubscriptionFrame): void {
		if (this.#released && !this.#terminal) {
			if (
				frame.kind === 'subscription.cancelled' ||
				frame.kind === 'subscription.end' ||
				frame.kind === 'subscription.reset'
			) {
				this.#retire();
			}
			return;
		}
		if (this.#terminal) {
			throw new BridgeProductSubscriptionFrameFailure(
				'subscription_post_terminal',
				'Bridge product subscription received a post-terminal frame.',
			);
		}
		if (
			frame.subscriptionId !== this.subscriptionId ||
			frame.subscriptionKind !== this.#protocol.kind ||
			frame.workerDerivationEpoch !== this.#admittedWorkerDerivationEpoch
		) {
			throw new BridgeProductSubscriptionFrameFailure(
				'subscription_identity_mismatch',
				'Bridge product subscription frame identity does not match its admission.',
			);
		}
		if (frame.subscriptionSequence !== this.#expectedSubscriptionSequence) {
			throw new BridgeProductSubscriptionFrameFailure(
				'subscription_sequence_mismatch',
				'Bridge product subscription sequence is not contiguous.',
			);
		}
		if (!this.#accepted) {
			if (frame.kind !== 'subscription.accepted' || frame.subscriptionSequence !== 0) {
				throw new BridgeProductSubscriptionFrameFailure(
					'subscription_acceptance_required',
					'Bridge product subscription requires accepted sequence zero.',
				);
			}
			this.#accepted = true;
			this.#currentInterestRevision = frame.interestRevision;
			this.#currentInterestHash = frame.interestSha256;
			this.#expectedSubscriptionSequence = 1;
			return;
		}
		if (frame.kind === 'subscription.accepted') {
			throw new BridgeProductSubscriptionFrameFailure(
				'subscription_duplicate_acceptance',
				'Bridge product subscription cannot accept twice.',
			);
		}
		this.#expectedSubscriptionSequence += 1;
		this.#acceptPostAdmissionFrame(frame);
	}

	fail(error: unknown): void {
		if (this.#terminal) return;
		this.#terminal = true;
		// An operation cut short by this subscription's own release ends it cleanly:
		// the consumer already has its terminal and native's frames still drain.
		const endedByRelease = error === this.#releaseReason;
		this.#rejectFrameWaiters(error);
		this.#recoveryGate?.reject(error);
		this.#recoveryGate = null;
		if (endedByRelease && !(error instanceof BridgeProductSubscriptionEpochRetiredError)) {
			this.#eventQueue.close(true);
		} else {
			this.#eventQueue.fail(error, true);
		}
		this.#onTerminal(
			this.subscriptionId,
			endedByRelease ? undefined : error,
			this.#nativeMayStillServe(),
		);
	}

	beginRecovery(): void {
		if (this.#terminal || this.#recoveryGate !== null) return;
		this.#recoveryGate = createBridgeProductDeferred<void>();
		void this.#recoveryGate.promise.catch((): void => {});
	}

	reconciliationClaim():
		| Extract<
				BridgeProductControlRequest,
				{ kind: 'workerSession.resync' }
		  >['activeSubscriptions'][number]
		| null {
		if (
			this.#terminal ||
			this.#admittedWorkerDerivationEpoch === null ||
			this.#currentInterestHash === null
		) {
			return null;
		}
		return {
			interestRevision: this.#currentInterestRevision,
			interestSha256: this.#currentInterestHash,
			subscriptionId: this.subscriptionId,
			subscriptionKind: this.#protocol.kind,
			// Ask native whether the old ID can serve the current surface. Its
			// reconciliation may require a new ID; never retag admitted frames.
			workerDerivationEpoch: this.#readWorkerDerivationEpochAtAdmission(),
		};
	}

	async applyReconciliation(outcome: BridgeProductResyncReconciliationOutcome): Promise<void> {
		if (
			outcome.subscriptionId !== this.subscriptionId ||
			outcome.subscriptionKind !== this.#protocol.kind
		) {
			throw new Error('Bridge product reconciliation references the wrong subscription.');
		}
		if (this.#released) {
			this.#retire();
			return;
		}
		switch (outcome.disposition) {
			case 'retained':
				this.#currentInterestRevision = outcome.interestRevision;
				this.#currentInterestHash = outcome.interestSha256;
				return;
			case 'reset': {
				const emptyState = this.#protocol.interestStateSchema.parse(
					this.#protocol.emptyInterestState(),
				);
				const emptyHash = await sha256Hex(this.#protocol.encodeInterestState(emptyState));
				if (this.#terminal) return;
				if (
					outcome.interestRevision <= this.#currentInterestRevision ||
					outcome.interestSha256 !== emptyHash
				) {
					throw new Error('Bridge product reset must advance to canonical empty interests.');
				}
				this.#resetReplay = {
					completion: this.#pendingBarrier?.completion ?? createBridgeProductDeferred<void>(),
					targetState: this.#pendingBarrier?.targetState ?? this.#currentInterestState,
				};
				void this.#resetReplay.completion.promise.catch((): void => {});
				this.#pendingBarrier = null;
				this.#currentInterestRevision = outcome.interestRevision;
				this.#currentInterestHash = outcome.interestSha256;
				this.#currentInterestState = emptyState;
				return;
			}
			case 'cancelled':
				this.#retire();
				return;
			case 'reopenRequired':
				if (
					(outcome.reason === 'epoch_advanced' || outcome.reason === 'native_missing') &&
					this.#admittedWorkerDerivationEpoch !== null &&
					outcome.requiredWorkerDerivationEpoch > this.#admittedWorkerDerivationEpoch
				) {
					// Native's surface floor passed this subscription's epoch.
					this.#retireForSurfaceEpoch(outcome.requiredWorkerDerivationEpoch);
					return;
				}
				this.#nativeTerminalObserved = true;
				this.fail(new BridgeProductSubscriptionResetError('snapshot_required'));
				return;
		}
	}

	async finishRecovery(): Promise<void> {
		const gate = this.#recoveryGate;
		if (gate === null) return;
		if (this.#terminal) return;
		if (this.#released) {
			// A released subscription restores no interests; it only drains.
			gate.resolve();
			this.#recoveryGate = null;
			return;
		}
		try {
			const replay = this.#resetReplay;
			if (replay !== null) await this.#replayResetInterests(replay);
			this.#resetReplay = null;
			gate.resolve();
			this.#recoveryGate = null;
		} catch (error) {
			this.fail(error);
			throw error;
		}
	}

	#acceptPostAdmissionFrame(
		frame: Exclude<BridgeProductSubscriptionFrame, { readonly kind: 'subscription.accepted' }>,
	): void {
		switch (frame.kind) {
			case 'subscription.data': {
				if (
					frame.interestRevision !== this.#currentInterestRevision ||
					frame.interestSha256 !== this.#currentInterestHash
				) {
					throw new BridgeProductSubscriptionFrameFailure(
						'subscription_interest_mismatch',
						'Bridge product subscription data arrived outside its committed barrier.',
					);
				}
				const parsedData = this.#protocol.dataSchema.safeParse(frame.data);
				if (!parsedData.success) {
					throw new BridgeProductSubscriptionFrameFailure(
						'subscription_payload_invalid',
						parsedData.error.message,
					);
				}
				const data = parsedData.data;
				if (this.#protocol.readEventSourceGeneration(data.event) !== frame.sourceGeneration) {
					throw new BridgeProductSubscriptionFrameFailure(
						'subscription_generation_mismatch',
						'Bridge product application event generation does not match its frame.',
					);
				}
				try {
					this.#eventQueue.push({
						data: data.event,
						metadataStreamId: frame.metadataStreamId,
						operationCorrelationId: frame.operationCorrelationId,
						sourceGeneration: frame.sourceGeneration,
						streamSequence: frame.streamSequence,
						subscriptionId: frame.subscriptionId,
						subscriptionKind: frame.subscriptionKind,
						subscriptionSequence: frame.subscriptionSequence,
						workerDerivationEpoch: frame.workerDerivationEpoch,
					});
				} catch {
					throw new BridgeProductSubscriptionFrameFailure(
						'subscription_queue_rejected',
						'Bridge product subscription event queue rejected a frame.',
					);
				}
				return;
			}
			case 'subscription.interestsCommitted':
				this.#acceptBarrier(frame);
				return;
			case 'subscription.cancelled':
			case 'subscription.end':
				this.#retire();
				return;
			case 'subscription.reset':
				if (frame.reason === 'epoch_retired') {
					// Native's surface floor passed this subscription's epoch before the
					// worker's own release ran; the worker already serves a newer one.
					this.#retireForSurfaceEpoch(this.#readWorkerDerivationEpochAtAdmission());
					return;
				}
				this.#nativeTerminalObserved = true;
				this.fail(new BridgeProductSubscriptionResetError(frame.reason));
				return;
		}
	}

	async #initialize(): Promise<void> {
		await this.#ensureMetadataStream();
		const initialOptions = this.#protocol.optionsSchema.parse(this.#initialOptions);
		const subscription = this.#protocol.openSchema.parse(
			this.#protocol.initialOpen(initialOptions),
		);
		// Admission records the epoch and queues the open control in one synchronous
		// turn, so a later surface advance always sees this admission and sequences
		// its release after the open.
		let opened: { readonly interestRevision: number; readonly interestSha256: string };
		try {
			opened = await this.#admitAtWorkerDerivationEpoch((workerDerivationEpoch) => {
				this.#admittedWorkerDerivationEpoch = workerDerivationEpoch;
				return this.#controlMux.openSubscription({
					subscription,
					subscriptionId: this.subscriptionId,
					workerDerivationEpoch,
				});
			});
		} catch (error) {
			if (error instanceof BridgeProductControlRequestError) this.#openRefusedByNative = true;
			throw error;
		}
		this.#openAcknowledged = true;
		if (
			this.#currentInterestHash !== null &&
			(this.#currentInterestRevision !== opened.interestRevision ||
				this.#currentInterestHash !== opened.interestSha256)
		) {
			throw new Error('Bridge product subscription open control and stream facts disagree.');
		}
		this.#currentInterestRevision = opened.interestRevision;
		this.#currentInterestHash = opened.interestSha256;
		await this.#updateTo(
			this.#protocol.updateOptionsSchema.parse(this.#protocol.initialUpdateOptions(initialOptions)),
		);
	}

	async #updateTo(options: TUpdateOptions): Promise<void> {
		this.#assertAcceptsInterests();
		const parsedOptions = this.#protocol.updateOptionsSchema.parse(options);
		const targetState = this.#protocol.interestStateSchema.parse(
			this.#protocol.interestStateForUpdate(parsedOptions),
		);
		const delta = this.#protocol.interestDeltaSchema.parse(
			this.#protocol.interestDelta(this.#currentInterestState, targetState),
		);
		const deltaItemCount = this.#protocol.interestDeltaItemCount(delta);
		if (deltaItemCount === 0) return;
		if (this.#currentInterestHash === null) {
			throw new Error('Bridge product subscription update preceded its open acceptance.');
		}
		const targetInterestSha256 = await sha256Hex(this.#protocol.encodeInterestState(targetState));
		while (this.#recoveryGate !== null) {
			// eslint-disable-next-line no-await-in-loop -- Recovery restores committed interests before admitting this prepared update.
			await this.#recoveryGate.promise;
		}
		this.#assertAcceptsInterests();
		const targetInterestRevision = this.#currentInterestRevision + 1;
		const updateId = this.#createIdentifier('subscription-update');
		const barrier = createBridgeProductDeferred<void>();
		void barrier.promise.catch((): void => {});
		this.#pendingBarrier = {
			completion: barrier,
			targetInterestRevision,
			targetInterestSha256,
			targetState,
			updateId,
		};
		try {
			await this.#controlMux.updateSubscriptionBatch({
				baseInterestRevision: this.#currentInterestRevision,
				baseInterestSha256: this.#currentInterestHash,
				batchCount: 1,
				batchIndex: 0,
				delta,
				subscriptionId: this.subscriptionId,
				targetInterestRevision,
				targetInterestSha256,
				totalDeltaItemCount: deltaItemCount,
				updateId,
				workerDerivationEpoch: this.#requiredAdmittedWorkerDerivationEpoch(),
			});
		} catch (error) {
			// A release requested while the update was in flight owns its outcome.
			throw this.#releaseReason ?? error;
		}
		await barrier.promise;
	}

	/** A terminal or released subscription never sends interests to native. */
	#assertAcceptsInterests(): void {
		if (this.#releaseReason !== null) throw this.#releaseReason;
		if (this.#terminal) throw new Error('Bridge product subscription is terminal.');
	}

	#acceptBarrier(
		frame: Extract<BridgeProductSubscriptionFrame, { kind: 'subscription.interestsCommitted' }>,
	): void {
		const pending = this.#pendingBarrier;
		if (
			pending === null ||
			frame.updateId !== pending.updateId ||
			frame.interestRevision !== pending.targetInterestRevision ||
			frame.interestSha256 !== pending.targetInterestSha256
		) {
			throw new Error('Bridge product subscription committed an unexpected interest barrier.');
		}
		this.#currentInterestRevision = pending.targetInterestRevision;
		this.#currentInterestHash = pending.targetInterestSha256;
		this.#currentInterestState = pending.targetState;
		this.#pendingBarrier = null;
		pending.completion.resolve();
	}

	#enqueue(
		operation: () => Promise<void>,
		admission: 'afterPriorSucceeds' | 'afterPriorSettles' = 'afterPriorSucceeds',
	): Promise<void> {
		const prior =
			admission === 'afterPriorSettles' ? this.#operation.catch((): void => {}) : this.#operation;
		const result = prior.then(async (): Promise<void> => {
			while (this.#recoveryGate !== null) {
				// eslint-disable-next-line no-await-in-loop -- Recheck admission if another recovery began while this gate resolved.
				await this.#recoveryGate.promise;
			}
			await operation();
		});
		this.#operation = result.catch((error: unknown): never => {
			this.fail(error);
			throw error;
		});
		void this.#operation.catch((): void => {});
		return result;
	}

	/**
	 * Queues the one release of this subscription. It sends the cancel once prior
	 * operations settle; the control mux is sequenced, so the cancel follows this
	 * subscription's own open and updates. A cancel is sent whenever native may
	 * still hold the subscription, even after a local failure.
	 */
	#queueRelease(reason: Error): Promise<void> {
		const operation = this.#enqueue(async (): Promise<void> => {
			this.#markReleased(reason);
			if (this.#openAcknowledged && !this.#nativeTerminalObserved) {
				await this.#releaseNativeSubscription();
			}
			this.#eventQueue.close(true);
		}, 'afterPriorSettles');
		this.#releaseOperation = operation;
		return operation;
	}

	#markReleased(reason: Error): void {
		if (this.#released) return;
		this.#released = true;
		this.#releaseReason = reason;
	}

	/**
	 * Sends the cancel control. A native refusal is not a failure of this
	 * subscription: native either refused a stale epoch after its surface floor
	 * advanced (it then ends the subscription itself with an `epoch_retired`
	 * reset) or had already ended it with a terminal frame still in flight. Either
	 * way the subscription stays released and drains until that terminal.
	 */
	async #releaseNativeSubscription(): Promise<void> {
		try {
			await this.#controlMux.cancelSubscription({
				subscriptionId: this.subscriptionId,
				subscriptionKind: this.#protocol.kind,
				workerDerivationEpoch: this.#requiredAdmittedWorkerDerivationEpoch(),
			});
		} catch (error) {
			if (error instanceof BridgeProductControlRequestError) return;
			throw error;
		}
	}

	#rejectFrameWaiters(error: unknown): void {
		this.#pendingBarrier?.completion.reject(error);
		this.#pendingBarrier = null;
		this.#resetReplay?.completion.reject(error);
		this.#resetReplay = null;
	}

	/** Native may still send frames: admitted, and native has not ended it. */
	#nativeMayStillServe(): boolean {
		return (
			this.#admittedWorkerDerivationEpoch !== null &&
			!this.#nativeTerminalObserved &&
			!this.#openRefusedByNative
		);
	}

	/** Native ended this subscription because its surface moved past its epoch. */
	#retireForSurfaceEpoch(nextWorkerDerivationEpoch: number): void {
		const retirement = new BridgeProductSubscriptionEpochRetiredError({
			nextWorkerDerivationEpoch,
			surface: this.#protocol.surface,
		});
		this.#eventQueue.fail(retirement, true);
		this.#retire(retirement);
	}

	/** Native ended this subscription. */
	#retire(waiterError: unknown = new Error('Bridge product subscription terminated.')): void {
		if (this.#terminal) return;
		this.#nativeTerminalObserved = true;
		this.#terminal = true;
		this.#rejectFrameWaiters(waiterError);
		this.#recoveryGate?.resolve();
		this.#recoveryGate = null;
		this.#eventQueue.close(true);
		this.#onTerminal(this.subscriptionId);
	}

	async #replayResetInterests(replay: ResetReplay<TInterestState>): Promise<void> {
		const delta = this.#protocol.interestDeltaSchema.parse(
			this.#protocol.interestDelta(this.#currentInterestState, replay.targetState),
		);
		const deltaItemCount = this.#protocol.interestDeltaItemCount(delta);
		if (deltaItemCount === 0) {
			replay.completion.resolve();
			return;
		}
		if (this.#currentInterestHash === null)
			throw new Error('Reset replay requires interest state.');
		const targetInterestRevision = this.#currentInterestRevision + 1;
		const targetInterestSha256 = await sha256Hex(
			this.#protocol.encodeInterestState(replay.targetState),
		);
		const updateId = this.#createIdentifier('subscription-update');
		this.#pendingBarrier = {
			completion: replay.completion,
			targetInterestRevision,
			targetInterestSha256,
			targetState: replay.targetState,
			updateId,
		};
		await this.#controlMux.updateSubscriptionBatch({
			baseInterestRevision: this.#currentInterestRevision,
			baseInterestSha256: this.#currentInterestHash,
			batchCount: 1,
			batchIndex: 0,
			delta,
			subscriptionId: this.subscriptionId,
			targetInterestRevision,
			targetInterestSha256,
			totalDeltaItemCount: deltaItemCount,
			updateId,
			workerDerivationEpoch: this.#requiredAdmittedWorkerDerivationEpoch(),
		});
		await replay.completion.promise;
	}

	#requiredAdmittedWorkerDerivationEpoch(): number {
		if (this.#admittedWorkerDerivationEpoch === null) {
			throw new Error('Bridge product subscription operation preceded its admission epoch.');
		}
		return this.#admittedWorkerDerivationEpoch;
	}
}

interface PendingSubscriptionBarrier<TInterestState> {
	readonly completion: BridgeProductDeferred<void>;
	readonly targetInterestRevision: number;
	readonly targetInterestSha256: string;
	readonly targetState: TInterestState;
	readonly updateId: string;
}

interface ResetReplay<TInterestState> {
	readonly completion: BridgeProductDeferred<void>;
	readonly targetState: TInterestState;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
	const ownedBytes = Uint8Array.from(bytes);
	const digestBytes = new Uint8Array(
		await globalThis.crypto.subtle.digest('SHA-256', ownedBytes.buffer),
	);
	return [...digestBytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
