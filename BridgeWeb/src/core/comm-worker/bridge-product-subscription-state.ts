import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
	type BridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type { BridgeProductControlMux } from './bridge-product-session-authority.js';
import type { BridgeProductMetadataFrame } from './bridge-product-session-contracts.js';
import {
	bridgeProductFileMetadataSubscriptionOptionsSchema,
	bridgeProductFileMetadataSubscriptionUpdateOptionsSchema,
	bridgeProductReviewMetadataSubscriptionOptionsSchema,
	bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema,
	type BridgeProductSubscriptionEvent,
	type BridgeProductSubscriptionInterestDeltaWire,
	type BridgeProductSubscriptionInterestState,
	type BridgeProductSubscriptionKind,
	type BridgeProductSubscriptionOptions,
	type BridgeProductSubscriptionUpdateOptions,
} from './bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from './bridge-product-subscription-interest-state-codec.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';

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

export interface BridgeProductSubscriptionStateProps<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> {
	readonly controlMux: Pick<
		BridgeProductControlMux,
		'cancelSubscription' | 'openSubscription' | 'updateSubscriptionBatch'
	>;
	readonly createIdentifier: (purpose: BridgeProductSubscriptionIdentifierPurpose) => string;
	readonly ensureMetadataStream: () => Promise<void>;
	readonly initialOptions: BridgeProductSubscriptionOptions<TSubscriptionKind>;
	readonly onTerminal: (subscriptionId: string) => void;
	readonly subscriptionId: string;
	readonly subscriptionKind: TSubscriptionKind;
	readonly workerDerivationEpoch: number;
}

export class BridgeProductSubscriptionState<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> implements BridgeProductSubscriptionFrameSink {
	#accepted = false;
	readonly #controlMux: BridgeProductSubscriptionStateProps<TSubscriptionKind>['controlMux'];
	readonly #createIdentifier: (purpose: BridgeProductSubscriptionIdentifierPurpose) => string;
	#currentInterestHash: string | null = null;
	#currentInterestRevision = 0;
	#currentInterestState: BridgeProductSubscriptionInterestState;
	readonly #ensureMetadataStream: () => Promise<void>;
	readonly #eventQueue = new BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<TSubscriptionKind>
	>(64);
	#expectedSubscriptionSequence = 0;
	readonly #initialOptions: BridgeProductSubscriptionOptions<TSubscriptionKind>;
	readonly #onTerminal: (subscriptionId: string) => void;
	#operation: Promise<void> = Promise.resolve();
	#pendingBarrier: PendingSubscriptionBarrier | null = null;
	#pendingCancel: BridgeProductDeferred<void> | null = null;
	readonly subscriptionId: string;
	readonly #subscriptionKind: TSubscriptionKind;
	#terminal = false;
	readonly #workerDerivationEpoch: number;

	constructor(props: BridgeProductSubscriptionStateProps<TSubscriptionKind>) {
		this.#controlMux = props.controlMux;
		this.#createIdentifier = props.createIdentifier;
		this.#ensureMetadataStream = props.ensureMetadataStream;
		this.#initialOptions = props.initialOptions;
		this.#onTerminal = props.onTerminal;
		this.subscriptionId = props.subscriptionId;
		this.#subscriptionKind = props.subscriptionKind;
		this.#workerDerivationEpoch = props.workerDerivationEpoch;
		this.#currentInterestState = emptyInterestState(props.subscriptionKind);
	}

	get publicSubscription(): BridgeProductSubscription<TSubscriptionKind> {
		return {
			cancel: (): Promise<void> => this.cancel(),
			events: this.#eventQueue,
			subscriptionId: this.subscriptionId,
			subscriptionKind: this.#subscriptionKind,
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

	update(options: BridgeProductSubscriptionUpdateOptions<TSubscriptionKind>): Promise<void> {
		return this.#enqueue(() => this.#updateTo(options));
	}

	cancel(): Promise<void> {
		return this.#enqueue(async (): Promise<void> => {
			if (this.#terminal) return;
			const cancelled = createBridgeProductDeferred<void>();
			this.#pendingCancel = cancelled;
			await this.#controlMux.cancelSubscription({
				subscriptionId: this.subscriptionId,
				subscriptionKind: this.#subscriptionKind,
				workerDerivationEpoch: this.#workerDerivationEpoch,
			});
			await cancelled.promise;
		});
	}

	acceptFrame(frame: BridgeProductSubscriptionFrame): void {
		if (this.#terminal)
			throw new Error('Bridge product subscription received a post-terminal frame.');
		if (
			frame.subscriptionId !== this.subscriptionId ||
			frame.subscriptionKind !== this.#subscriptionKind ||
			frame.workerDerivationEpoch !== this.#workerDerivationEpoch
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
			case 'subscription.data':
				if (
					frame.interestRevision !== this.#currentInterestRevision ||
					frame.interestSha256 !== this.#currentInterestHash
				) {
					throw new Error(
						'Bridge product subscription data arrived outside its committed barrier.',
					);
				}
				this.#eventQueue.push(subscriptionEventForKind(frame, this.#subscriptionKind));
				return;
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
		const opened = await this.#controlMux.openSubscription({
			subscription: subscriptionOpenForOptions(this.#subscriptionKind, this.#initialOptions),
			subscriptionId: this.subscriptionId,
			workerDerivationEpoch: this.#workerDerivationEpoch,
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
		await this.#updateTo(initialUpdateOptions(this.#subscriptionKind, this.#initialOptions));
	}

	async #updateTo(
		options: BridgeProductSubscriptionUpdateOptions<TSubscriptionKind>,
	): Promise<void> {
		if (this.#terminal) throw new Error('Bridge product subscription is terminal.');
		const targetState = interestStateForUpdate(this.#subscriptionKind, options);
		const delta = interestDelta(this.#currentInterestState, targetState);
		const deltaItemCount = interestDeltaItemCount(delta);
		if (deltaItemCount === 0) return;
		if (this.#currentInterestHash === null) {
			throw new Error('Bridge product subscription update preceded its open acceptance.');
		}
		const targetInterestRevision = this.#currentInterestRevision + 1;
		const targetInterestSha256 = await sha256Hex(
			encodeBridgeProductSubscriptionInterestState(targetState),
		);
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
			workerDerivationEpoch: this.#workerDerivationEpoch,
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
}

interface PendingSubscriptionBarrier {
	readonly completion: BridgeProductDeferred<void>;
	readonly targetInterestRevision: number;
	readonly targetInterestSha256: string;
	readonly targetState: BridgeProductSubscriptionInterestState;
	readonly updateId: string;
}

function emptyInterestState(
	subscriptionKind: BridgeProductSubscriptionKind,
): BridgeProductSubscriptionInterestState {
	return subscriptionKind === 'file.metadata'
		? { interests: [], pathScope: [], subscriptionKind: 'file.metadata' }
		: { interests: [], subscriptionKind: 'review.metadata' };
}

function subscriptionOpenForOptions<TSubscriptionKind extends BridgeProductSubscriptionKind>(
	subscriptionKind: TSubscriptionKind,
	options: BridgeProductSubscriptionOptions<TSubscriptionKind>,
): Parameters<
	BridgeProductSubscriptionStateProps<TSubscriptionKind>['controlMux']['openSubscription']
>[0]['subscription'] {
	if (subscriptionKind === 'file.metadata') {
		const parsed = bridgeProductFileMetadataSubscriptionOptionsSchema.parse(options);
		return { source: parsed.source, subscriptionKind: 'file.metadata' };
	}
	bridgeProductReviewMetadataSubscriptionOptionsSchema.parse(options);
	return { subscriptionKind: 'review.metadata' };
}

function initialUpdateOptions<TSubscriptionKind extends BridgeProductSubscriptionKind>(
	subscriptionKind: TSubscriptionKind,
	options: BridgeProductSubscriptionOptions<TSubscriptionKind>,
): BridgeProductSubscriptionUpdateOptions<TSubscriptionKind> {
	if (subscriptionKind === 'file.metadata') {
		const parsed = bridgeProductFileMetadataSubscriptionOptionsSchema.parse(options);
		return bridgeProductFileMetadataSubscriptionUpdateOptionsSchema.parse({
			interests: parsed.interests,
			pathScope: parsed.pathScope,
		});
	}
	return bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.parse(options);
}

function interestStateForUpdate<TSubscriptionKind extends BridgeProductSubscriptionKind>(
	subscriptionKind: TSubscriptionKind,
	options: BridgeProductSubscriptionUpdateOptions<TSubscriptionKind>,
): BridgeProductSubscriptionInterestState {
	return subscriptionKind === 'file.metadata'
		? {
				...bridgeProductFileMetadataSubscriptionUpdateOptionsSchema.parse(options),
				subscriptionKind: 'file.metadata',
			}
		: {
				...bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.parse(options),
				subscriptionKind: 'review.metadata',
			};
}

function interestDelta(
	current: BridgeProductSubscriptionInterestState,
	target: BridgeProductSubscriptionInterestState,
): BridgeProductSubscriptionInterestDeltaWire {
	if (target.subscriptionKind === 'review.metadata') {
		if (current.subscriptionKind !== 'review.metadata') {
			throw new Error('Bridge product interest update crossed subscription kinds.');
		}
		const currentLanes = reviewInterestLanes(current);
		const targetLanes = reviewInterestLanes(target);
		return {
			add: [...targetLanes].flatMap(([itemId, lane]) =>
				currentLanes.get(itemId) === lane ? [] : [{ itemId, lane }],
			),
			removeItemIds: [...currentLanes.keys()].filter((itemId) => !targetLanes.has(itemId)),
			subscriptionKind: 'review.metadata',
		};
	}
	if (current.subscriptionKind !== 'file.metadata') {
		throw new Error('Bridge product interest update crossed subscription kinds.');
	}
	const currentLanes = fileInterestLanes(current);
	const targetLanes = fileInterestLanes(target);
	const currentScope = new Set(current.pathScope);
	const targetScope = new Set(target.pathScope);
	return {
		add: [...targetLanes].flatMap(([path, lane]) =>
			currentLanes.get(path) === lane ? [] : [{ lane, path }],
		),
		addPathScope: [...targetScope].filter((path) => !currentScope.has(path)),
		removePathScope: [...currentScope].filter((path) => !targetScope.has(path)),
		removePaths: [...currentLanes.keys()].filter((path) => !targetLanes.has(path)),
		subscriptionKind: 'file.metadata',
	};
}

function reviewInterestLanes(
	state: Extract<BridgeProductSubscriptionInterestState, { subscriptionKind: 'review.metadata' }>,
): ReadonlyMap<string, (typeof state.interests)[number]['lane']> {
	return new Map(
		state.interests.flatMap((interest) =>
			interest.itemIds.map((itemId) => [itemId, interest.lane] as const),
		),
	);
}

function fileInterestLanes(
	state: Extract<BridgeProductSubscriptionInterestState, { subscriptionKind: 'file.metadata' }>,
): ReadonlyMap<string, (typeof state.interests)[number]['lane']> {
	return new Map(
		state.interests.flatMap((interest) =>
			interest.paths.map((path) => [path, interest.lane] as const),
		),
	);
}

function interestDeltaItemCount(delta: BridgeProductSubscriptionInterestDeltaWire): number {
	return delta.subscriptionKind === 'review.metadata'
		? delta.add.length + delta.removeItemIds.length
		: delta.add.length +
				delta.addPathScope.length +
				delta.removePathScope.length +
				delta.removePaths.length;
}

function subscriptionEventForKind<TSubscriptionKind extends BridgeProductSubscriptionKind>(
	frame: Extract<BridgeProductSubscriptionFrame, { kind: 'subscription.data' }>,
	expectedKind: TSubscriptionKind,
): BridgeProductSubscriptionEvent<TSubscriptionKind> {
	if (frame.subscriptionKind !== expectedKind) {
		throw new Error('Bridge product subscription data crossed subscription kinds.');
	}
	return frame.data.event;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
	const ownedBytes = Uint8Array.from(bytes);
	const digestBytes = new Uint8Array(
		await globalThis.crypto.subtle.digest('SHA-256', ownedBytes.buffer),
	);
	return [...digestBytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
