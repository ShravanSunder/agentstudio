import type { BridgeProductSurface } from './bridge-product-contract-primitives.js';
import type { BridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import {
	createBridgeWorkerRenderFulfillment,
	reduceBridgeWorkerRenderFulfillment,
	isBridgeWorkerRenderReceiptRejectionError,
	type BridgeWorkerRenderDispositionReceipt,
	type BridgeWorkerRenderFulfillmentState,
	type BridgeWorkerRenderReceiptIdentity,
} from './bridge-worker-render-fulfillment.js';

export interface BridgeWorkerRenderFulfillmentRegistryContext {
	readonly paneSessionId: string;
	readonly surface: BridgeProductSurface;
	readonly workerInstanceId: string;
}

export type BridgeWorkerRenderFulfillmentIdentifierPurpose =
	| 'attempt'
	| 'publication'
	| 'submission';

export interface CreateBridgeWorkerRenderFulfillmentRegistryProps {
	readonly context: BridgeWorkerRenderFulfillmentRegistryContext;
	readonly createIdentifier?: (purpose: BridgeWorkerRenderFulfillmentIdentifierPurpose) => string;
	readonly now?: () => number;
	readonly receiptLeaseDurationMilliseconds: number;
	readonly retryBackoffMilliseconds: number;
}

export interface BeginBridgeWorkerRenderPublicationProps {
	readonly job: BridgeWorkerPierreRenderJob;
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}

export type BeginBridgeWorkerRenderPublicationResult = Readonly<
	| {
			receiptIdentity: BridgeWorkerRenderReceiptIdentity;
			shouldPublish: true;
			state: BridgeWorkerRenderFulfillmentState;
			status: 'published';
	  }
	| {
			receiptIdentity: BridgeWorkerRenderReceiptIdentity;
			shouldPublish: false;
			state: BridgeWorkerRenderFulfillmentState;
			status: 'duplicate' | 'retry_wait';
	  }
>;

export type ApplyBridgeWorkerRenderDispositionResult = Readonly<
	| {
			readonly state: BridgeWorkerRenderFulfillmentState;
			readonly status: 'accepted' | 'duplicate';
	  }
	| {
			readonly reason: string;
			readonly state: BridgeWorkerRenderFulfillmentState | null;
			readonly status: 'rejected';
	  }
>;

const bridgeWorkerRenderWindowKeyMaximumLength = 4096;

export class BridgeWorkerRenderFulfillmentRegistry {
	readonly #context: BridgeWorkerRenderFulfillmentRegistryContext;
	readonly #createIdentifier: (purpose: BridgeWorkerRenderFulfillmentIdentifierPurpose) => string;
	readonly #fulfillmentByItemId = new Map<string, BridgeWorkerRenderFulfillmentState>();
	readonly #now: () => number;
	readonly #receiptLeaseDurationMilliseconds: number;
	readonly #retryBackoffMilliseconds: number;

	constructor(props: CreateBridgeWorkerRenderFulfillmentRegistryProps) {
		assertBridgeWorkerRenderPositiveDuration(
			props.receiptLeaseDurationMilliseconds,
			'receipt lease duration',
		);
		assertBridgeWorkerRenderNonnegativeDuration(props.retryBackoffMilliseconds, 'retry backoff');
		this.#context = Object.freeze({ ...props.context });
		this.#createIdentifier =
			props.createIdentifier ??
			((purpose): string => `${purpose}-${globalThis.crypto.randomUUID()}`);
		this.#now = props.now ?? performance.now.bind(performance);
		this.#receiptLeaseDurationMilliseconds = props.receiptLeaseDurationMilliseconds;
		this.#retryBackoffMilliseconds = props.retryBackoffMilliseconds;
	}

	beginPublication(
		props: BeginBridgeWorkerRenderPublicationProps,
	): BeginBridgeWorkerRenderPublicationResult {
		const windowKey = bridgeWorkerRenderWindowKeyForJob(props.job);
		let existingState = this.#fulfillmentByItemId.get(props.job.itemId) ?? null;
		if (
			existingState !== null &&
			existingState.identity.windowKey === windowKey &&
			existingState.workerDerivationEpoch === props.workerDerivationEpoch
		) {
			if (existingState.stage === 'retry_wait') {
				existingState = this.#releaseRetryIfReady(existingState, this.#now());
			}
			if (existingState.stage !== 'desired') {
				return Object.freeze({
					receiptIdentity: activeBridgeWorkerRenderReceiptIdentity(existingState),
					shouldPublish: false,
					state: existingState,
					status: existingState.stage === 'retry_wait' ? 'retry_wait' : 'duplicate',
				});
			}
		}

		const publicationState =
			existingState === null ||
			existingState.identity.windowKey !== windowKey ||
			existingState.workerDerivationEpoch !== props.workerDerivationEpoch
				? createBridgeWorkerRenderFulfillment({
						...this.#context,
						identity: Object.freeze({ windowKey }),
						itemId: props.job.itemId,
						publicationId: this.#createIdentifier('publication'),
						publicationSequence: props.publicationSequence,
						submissionId: this.#createIdentifier('submission'),
						workerDerivationEpoch: props.workerDerivationEpoch,
					})
				: existingState;
		const preparingState = reduceBridgeWorkerRenderFulfillment(publicationState, {
			kind: 'preparation.started',
		});
		const publishedAtMilliseconds = this.#now();
		const publishedState = reduceBridgeWorkerRenderFulfillment(preparingState, {
			attemptId: this.#createIdentifier('attempt'),
			kind: 'publication.started',
			publishedAtMilliseconds,
			receiptLeaseExpiresAtMilliseconds:
				publishedAtMilliseconds + this.#receiptLeaseDurationMilliseconds,
		});
		this.#fulfillmentByItemId.set(props.job.itemId, publishedState);
		return Object.freeze({
			receiptIdentity: activeBridgeWorkerRenderReceiptIdentity(publishedState),
			shouldPublish: true,
			state: publishedState,
			status: 'published',
		});
	}

	applyDisposition(
		receipt: BridgeWorkerRenderDispositionReceipt,
	): ApplyBridgeWorkerRenderDispositionResult {
		const currentState = this.#fulfillmentByItemId.get(receipt.itemId) ?? null;
		if (currentState === null) {
			return Object.freeze({
				reason: 'Bridge render disposition has no matching worker publication.',
				state: null,
				status: 'rejected',
			});
		}
		let nextState: BridgeWorkerRenderFulfillmentState;
		try {
			nextState = reduceBridgeWorkerRenderFulfillment(currentState, receipt);
		} catch (error) {
			if (!isBridgeWorkerRenderReceiptRejectionError(error)) {
				throw error;
			}
			return Object.freeze({
				reason: bridgeWorkerRenderRegistryRejectionReason(error),
				state: currentState,
				status: 'rejected',
			});
		}
		if (nextState === currentState) {
			return Object.freeze({ state: currentState, status: 'duplicate' });
		}
		this.#fulfillmentByItemId.set(receipt.itemId, nextState);
		return Object.freeze({ state: nextState, status: 'accepted' });
	}

	expireReceiptLeases(atMilliseconds: number = this.#now()): readonly string[] {
		const expiredItemIds: string[] = [];
		for (const [itemId, currentState] of this.#fulfillmentByItemId) {
			const activeAttempt = currentState.activeAttempt;
			if (
				activeAttempt === null ||
				atMilliseconds < activeAttempt.receiptLeaseExpiresAtMilliseconds
			) {
				continue;
			}
			const nextState = reduceBridgeWorkerRenderFulfillment(currentState, {
				...activeBridgeWorkerRenderReceiptIdentity(currentState),
				atMilliseconds,
				kind: 'receiptLease.expired',
				retryAtMilliseconds: atMilliseconds + this.#retryBackoffMilliseconds,
			});
			this.#fulfillmentByItemId.set(itemId, nextState);
			expiredItemIds.push(itemId);
		}
		return Object.freeze(expiredItemIds);
	}

	releaseReadyRetries(atMilliseconds: number = this.#now()): readonly string[] {
		const releasedItemIds: string[] = [];
		for (const [itemId, currentState] of this.#fulfillmentByItemId) {
			const nextState = this.#releaseRetryIfReady(currentState, atMilliseconds);
			if (nextState === currentState) continue;
			this.#fulfillmentByItemId.set(itemId, nextState);
			releasedItemIds.push(itemId);
		}
		return Object.freeze(releasedItemIds);
	}

	nextLifecycleWakeAtMilliseconds(): number | null {
		let nextWakeAtMilliseconds: number | null = null;
		for (const currentState of this.#fulfillmentByItemId.values()) {
			const candidateWakeAtMilliseconds =
				currentState.stage === 'retry_wait'
					? currentState.retryAtMilliseconds
					: currentState.activeAttempt?.receiptLeaseExpiresAtMilliseconds;
			if (
				candidateWakeAtMilliseconds !== null &&
				candidateWakeAtMilliseconds !== undefined &&
				(nextWakeAtMilliseconds === null || candidateWakeAtMilliseconds < nextWakeAtMilliseconds)
			) {
				nextWakeAtMilliseconds = candidateWakeAtMilliseconds;
			}
		}
		return nextWakeAtMilliseconds;
	}

	getItemState(itemId: string): BridgeWorkerRenderFulfillmentState | null {
		return this.#fulfillmentByItemId.get(itemId) ?? null;
	}

	resetPublications(): void {
		this.#fulfillmentByItemId.clear();
	}

	#releaseRetryIfReady(
		state: BridgeWorkerRenderFulfillmentState,
		atMilliseconds: number,
	): BridgeWorkerRenderFulfillmentState {
		if (
			state.stage !== 'retry_wait' ||
			state.retryAtMilliseconds === null ||
			atMilliseconds < state.retryAtMilliseconds
		) {
			return state;
		}
		const nextState = reduceBridgeWorkerRenderFulfillment(state, {
			atMilliseconds,
			kind: 'retry.ready',
		});
		this.#fulfillmentByItemId.set(state.itemId, nextState);
		return nextState;
	}
}

export function bridgeWorkerRenderWindowKeyForJob(job: BridgeWorkerPierreRenderJob): string {
	const windowKey = JSON.stringify([
		'bridge-render-window-v1',
		job.itemId,
		job.renderKind,
		job.contentCacheKey,
		job.contentHash,
		job.window.startLine,
		job.window.endLine,
		job.window.totalLineCount,
	]);
	if (windowKey.length > bridgeWorkerRenderWindowKeyMaximumLength) {
		throw new Error('Bridge render semantic window identity exceeds its bounded wire shape.');
	}
	return windowKey;
}

function activeBridgeWorkerRenderReceiptIdentity(
	state: BridgeWorkerRenderFulfillmentState,
): BridgeWorkerRenderReceiptIdentity {
	if (state.activeAttempt !== null) {
		return Object.freeze({
			attemptId: state.activeAttempt.attemptId,
			itemId: state.itemId,
			paneSessionId: state.paneSessionId,
			publicationId: state.publicationId,
			publicationSequence: state.publicationSequence,
			submissionId: state.submissionId,
			surface: state.surface,
			windowKey: state.identity.windowKey,
			workerDerivationEpoch: state.workerDerivationEpoch,
			workerInstanceId: state.workerInstanceId,
		});
	}
	if (state.paintedResidency !== null) {
		return state.paintedResidency;
	}
	const latestClosedAttempt = state.closedAttempts.at(-1);
	if (latestClosedAttempt !== undefined) {
		return Object.freeze({
			attemptId: latestClosedAttempt.attemptId,
			itemId: state.itemId,
			paneSessionId: state.paneSessionId,
			publicationId: state.publicationId,
			publicationSequence: state.publicationSequence,
			submissionId: state.submissionId,
			surface: state.surface,
			windowKey: state.identity.windowKey,
			workerDerivationEpoch: state.workerDerivationEpoch,
			workerInstanceId: state.workerInstanceId,
		});
	}
	throw new Error('Bridge render fulfillment has no receipt-bearing attempt.');
}

function assertBridgeWorkerRenderPositiveDuration(value: number, name: string): void {
	if (!Number.isFinite(value) || value <= 0) {
		throw new Error(`Bridge render ${name} must be finite and positive.`);
	}
}

function assertBridgeWorkerRenderNonnegativeDuration(value: number, name: string): void {
	if (!Number.isFinite(value) || value < 0) {
		throw new Error(`Bridge render ${name} must be finite and nonnegative.`);
	}
}

function bridgeWorkerRenderRegistryRejectionReason(error: unknown): string {
	return error instanceof Error ? error.message : 'Bridge render disposition was rejected.';
}
