import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
	type BridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type { BridgeProductMetadataApplicationProtocol } from './bridge-product-metadata-application-protocol.js';
import type { BridgeProductMetadataFrame } from './bridge-product-session-contracts.js';

export type BridgeProductSubscriptionIdentifierPurpose = 'subscription-update';

export type BridgeProductSubscriptionFrame = Exclude<
	BridgeProductMetadataFrame,
	| { readonly kind: 'content.cancelled' }
	| { readonly kind: 'metadataStream.accepted' }
	| { readonly kind: 'metadataStream.error' }
	| { readonly kind: 'pane.presentation' }
	| { readonly kind: 'pane.surfaceSelectionRequested' }
>;

export interface BridgeProductSubscriptionFrameSink {
	readonly subscriptionId: string;
	acceptFrame(frame: BridgeProductSubscriptionFrame): void;
	fail(error: unknown): void;
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
	readonly onTerminal: (subscriptionId: string) => void;
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
	readonly #eventQueue = new BridgeProductBoundedAsyncQueue<TData['event']>(64);
	#expectedSubscriptionSequence = 0;
	readonly #initialOptions: TOptions;
	readonly #onTerminal: (subscriptionId: string) => void;
	#operation: Promise<void> = Promise.resolve();
	#pendingBarrier: PendingSubscriptionBarrier<TInterestState> | null = null;
	#pendingCancel: BridgeProductDeferred<void> | null = null;
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
		this.subscriptionId = props.subscriptionId;
		this.#currentInterestState = props.protocol.interestStateSchema.parse(
			props.protocol.emptyInterestState(),
		);
	}

	get publicSubscription(): {
		readonly events: AsyncIterable<TData['event']>;
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

	update(options: TUpdateOptions): Promise<void> {
		return this.#enqueue(() => this.#updateTo(options));
	}

	cancel(): Promise<void> {
		return this.#enqueue(async (): Promise<void> => {
			if (this.#terminal) return;
			const cancelled = createBridgeProductDeferred<void>();
			this.#pendingCancel = cancelled;
			await this.#controlMux.cancelSubscription({
				subscriptionId: this.subscriptionId,
				subscriptionKind: this.#protocol.kind,
				workerDerivationEpoch: this.#requiredAdmittedWorkerDerivationEpoch(),
			});
			await cancelled.promise;
		});
	}

	acceptFrame(frame: BridgeProductSubscriptionFrame): void {
		if (this.#terminal) {
			throw new Error('Bridge product subscription received a post-terminal frame.');
		}
		if (
			frame.subscriptionId !== this.subscriptionId ||
			frame.subscriptionKind !== this.#protocol.kind ||
			frame.workerDerivationEpoch !== this.#admittedWorkerDerivationEpoch
		) {
			throw new Error('Bridge product subscription frame identity does not match its admission.');
		}
		if (frame.subscriptionSequence !== this.#expectedSubscriptionSequence) {
			throw new Error('Bridge product subscription sequence is not contiguous.');
		}
		if (!this.#accepted) {
			if (frame.kind !== 'subscription.accepted' || frame.subscriptionSequence !== 0) {
				throw new Error('Bridge product subscription requires accepted sequence zero.');
			}
			this.#accepted = true;
			this.#currentInterestRevision = frame.interestRevision;
			this.#currentInterestHash = frame.interestSha256;
			this.#expectedSubscriptionSequence = 1;
			return;
		}
		if (frame.kind === 'subscription.accepted') {
			throw new Error('Bridge product subscription cannot accept twice.');
		}
		this.#expectedSubscriptionSequence += 1;
		this.#acceptPostAdmissionFrame(frame);
	}

	fail(error: unknown): void {
		if (this.#terminal) return;
		this.#terminal = true;
		this.#pendingBarrier?.completion.reject(error);
		this.#pendingBarrier = null;
		this.#pendingCancel?.reject(error);
		this.#pendingCancel = null;
		this.#eventQueue.fail(error, true);
		this.#onTerminal(this.subscriptionId);
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
					throw new Error(
						'Bridge product subscription data arrived outside its committed barrier.',
					);
				}
				const data = this.#protocol.dataSchema.parse(frame.data);
				if (this.#protocol.readEventSourceGeneration(data.event) !== frame.sourceGeneration) {
					throw new Error('Bridge product application event generation does not match its frame.');
				}
				this.#eventQueue.push(data.event);
				return;
			}
			case 'subscription.interestsCommitted':
				this.#acceptBarrier(frame);
				return;
			case 'subscription.cancelled':
				this.#pendingCancel?.resolve();
				this.#retire();
				return;
			case 'subscription.end':
				this.#retire();
				return;
			case 'subscription.reset':
				this.fail(new Error(`Bridge product subscription reset: ${frame.reason}.`));
				return;
		}
	}

	async #initialize(): Promise<void> {
		await this.#ensureMetadataStream();
		const workerDerivationEpoch = this.#readWorkerDerivationEpochAtAdmission();
		this.#admittedWorkerDerivationEpoch = workerDerivationEpoch;
		const initialOptions = this.#protocol.optionsSchema.parse(this.#initialOptions);
		const subscription = this.#protocol.openSchema.parse(
			this.#protocol.initialOpen(initialOptions),
		);
		const opened = await this.#controlMux.openSubscription({
			subscription,
			subscriptionId: this.subscriptionId,
			workerDerivationEpoch,
		});
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
		if (this.#terminal) throw new Error('Bridge product subscription is terminal.');
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
		const targetInterestRevision = this.#currentInterestRevision + 1;
		const targetInterestSha256 = await sha256Hex(this.#protocol.encodeInterestState(targetState));
		const updateId = this.#createIdentifier('subscription-update');
		const barrier = createBridgeProductDeferred<void>();
		this.#pendingBarrier = {
			completion: barrier,
			targetInterestRevision,
			targetInterestSha256,
			targetState,
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
		await barrier.promise;
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

	#enqueue(operation: () => Promise<void>): Promise<void> {
		const result = this.#operation.then(operation);
		this.#operation = result.catch((error: unknown): never => {
			this.fail(error);
			throw error;
		});
		void this.#operation.catch((): void => {});
		return result;
	}

	#retire(): void {
		this.#terminal = true;
		this.#pendingBarrier?.completion.reject(new Error('Bridge product subscription terminated.'));
		this.#pendingBarrier = null;
		this.#pendingCancel?.resolve();
		this.#pendingCancel = null;
		this.#eventQueue.close(true);
		this.#onTerminal(this.subscriptionId);
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

async function sha256Hex(bytes: Uint8Array): Promise<string> {
	const ownedBytes = Uint8Array.from(bytes);
	const digestBytes = new Uint8Array(
		await globalThis.crypto.subtle.digest('SHA-256', ownedBytes.buffer),
	);
	return [...digestBytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
