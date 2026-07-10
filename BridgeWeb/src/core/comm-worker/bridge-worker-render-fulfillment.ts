import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductSurfaceSchema,
	type BridgeProductSurface,
} from './bridge-product-contract-primitives.js';
import type { BridgeWorkerSemanticWindowIdentity } from './bridge-worker-semantic-identity.js';

const bridgeWorkerRenderTimestampSchema = z
	.number()
	.finite()
	.nonnegative()
	.max(Number.MAX_SAFE_INTEGER);
const bridgeWorkerRenderWindowKeySchema = z.string().min(1).max(4096);

const bridgeWorkerRenderReceiptIdentityShape = {
	attemptId: bridgeProductIdentifierSchema,
	paneSessionId: bridgeProductIdentifierSchema,
	submissionId: bridgeProductIdentifierSchema,
	surface: bridgeProductSurfaceSchema,
	windowKey: bridgeWorkerRenderWindowKeySchema,
	workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

const bridgeWorkerRenderReceiptBaseShape = {
	...bridgeWorkerRenderReceiptIdentityShape,
	kind: z.literal('render.disposition'),
	receivedAtMilliseconds: bridgeWorkerRenderTimestampSchema,
} as const;

const bridgeWorkerRenderFulfillmentIdentitySchema = z
	.object({
		paneSessionId: bridgeProductIdentifierSchema,
		submissionId: bridgeProductIdentifierSchema,
		surface: bridgeProductSurfaceSchema,
		workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
		workerInstanceId: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeWorkerRenderRejectionReasonSchema = z.enum([
	'foreign_context',
	'stale_attempt',
	'stale_submission',
	'window_mismatch',
	'already_terminal',
]);

export const bridgeWorkerRenderDispositionReceiptSchema = z.discriminatedUnion('disposition', [
	z
		.object({
			...bridgeWorkerRenderReceiptBaseShape,
			disposition: z.literal('queued'),
		})
		.strict(),
	z
		.object({
			...bridgeWorkerRenderReceiptBaseShape,
			disposition: z.literal('applied'),
		})
		.strict(),
	z
		.object({
			...bridgeWorkerRenderReceiptBaseShape,
			disposition: z.literal('painted'),
		})
		.strict(),
	z
		.object({
			...bridgeWorkerRenderReceiptBaseShape,
			disposition: z.literal('rejected'),
			reason: bridgeWorkerRenderRejectionReasonSchema,
			retryAtMilliseconds: bridgeWorkerRenderTimestampSchema,
		})
		.strict(),
	z
		.object({
			...bridgeWorkerRenderReceiptBaseShape,
			disposition: z.literal('superseded'),
			reason: bridgeWorkerRenderRejectionReasonSchema,
			retryAtMilliseconds: bridgeWorkerRenderTimestampSchema,
		})
		.strict(),
]);

export const bridgeWorkerReceiptLeaseExpiredSchema = z
	.object({
		...bridgeWorkerRenderReceiptIdentityShape,
		atMilliseconds: bridgeWorkerRenderTimestampSchema,
		kind: z.literal('receiptLease.expired'),
		retryAtMilliseconds: bridgeWorkerRenderTimestampSchema,
	})
	.strict();

export const bridgeWorkerSelectionAcceptedReceiptSchema = z
	.object({
		...bridgeWorkerRenderReceiptIdentityShape,
		atMilliseconds: bridgeWorkerRenderTimestampSchema,
		kind: z.literal('selection.accepted'),
		uiIntentRevision: bridgeProductNonnegativeSequenceSchema,
		validationLeaseExpiresAtMilliseconds: bridgeWorkerRenderTimestampSchema,
	})
	.strict();

export const bridgeWorkerRenderReceiptTransitionSchema = z.discriminatedUnion('kind', [
	bridgeWorkerRenderDispositionReceiptSchema,
	bridgeWorkerReceiptLeaseExpiredSchema,
	bridgeWorkerSelectionAcceptedReceiptSchema,
]);

export type BridgeWorkerRenderDisposition = z.infer<
	typeof bridgeWorkerRenderDispositionReceiptSchema
>['disposition'];

export type BridgeWorkerRenderRejectionReason = z.infer<
	typeof bridgeWorkerRenderRejectionReasonSchema
>;

export interface BridgeWorkerRenderContext {
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
	readonly surface: BridgeProductSurface;
	readonly workerDerivationEpoch: number;
}

export interface BridgeWorkerRenderReceiptIdentity extends BridgeWorkerRenderContext {
	readonly attemptId: string;
	readonly submissionId: string;
	readonly windowKey: string;
}

type BridgeWorkerRenderDispositionReceipt = Readonly<
	z.infer<typeof bridgeWorkerRenderDispositionReceiptSchema>
>;
type BridgeWorkerReceiptLeaseExpired = Readonly<
	z.infer<typeof bridgeWorkerReceiptLeaseExpiredSchema>
>;
type BridgeWorkerSelectionAcceptedReceipt = Readonly<
	z.infer<typeof bridgeWorkerSelectionAcceptedReceiptSchema>
>;
type BridgeWorkerRenderReceiptTransition = Readonly<
	z.infer<typeof bridgeWorkerRenderReceiptTransitionSchema>
>;

export type BridgeWorkerRenderFulfillmentStage =
	| 'desired'
	| 'preparing'
	| 'published'
	| 'queued'
	| 'applied'
	| 'painted'
	| 'retry_wait';

interface BridgeWorkerActiveRenderAttempt {
	readonly attemptId: string;
	readonly receiptLeaseExpiresAtMilliseconds: number;
	readonly highestDisposition: 'queued' | 'applied' | null;
}

type BridgeWorkerClosedRenderAttempt =
	| {
			readonly attemptId: string;
			readonly disposition: 'painted' | 'lease_expired';
	  }
	| {
			readonly attemptId: string;
			readonly disposition: 'rejected' | 'superseded';
			readonly reason: BridgeWorkerRenderRejectionReason;
	  };

export type BridgeWorkerPaintedResidency = BridgeWorkerRenderReceiptIdentity;

export interface BridgeWorkerRenderFulfillmentState extends BridgeWorkerRenderContext {
	readonly identity: BridgeWorkerSemanticWindowIdentity;
	readonly submissionId: string;
	readonly stage: BridgeWorkerRenderFulfillmentStage;
	readonly isDesired: boolean;
	readonly activeAttempt: BridgeWorkerActiveRenderAttempt | null;
	readonly attemptIds: readonly string[];
	readonly closedAttempts: readonly BridgeWorkerClosedRenderAttempt[];
	readonly retryAtMilliseconds: number | null;
	readonly paintedResidency: BridgeWorkerPaintedResidency | null;
	readonly acceptedUiIntentRevision: number | null;
}

export type BridgeWorkerRenderFulfillmentEvent =
	| { readonly kind: 'preparation.started' }
	| {
			readonly kind: 'publication.started';
			readonly attemptId: string;
			readonly publishedAtMilliseconds: number;
			readonly receiptLeaseExpiresAtMilliseconds: number;
	  }
	| BridgeWorkerRenderDispositionReceipt
	| BridgeWorkerReceiptLeaseExpired
	| { readonly kind: 'retry.ready'; readonly atMilliseconds: number }
	| BridgeWorkerSelectionAcceptedReceipt;

export function createBridgeWorkerRenderFulfillment(props: {
	readonly identity: BridgeWorkerSemanticWindowIdentity;
	readonly paneSessionId: string;
	readonly submissionId: string;
	readonly surface: BridgeProductSurface;
	readonly workerDerivationEpoch: number;
	readonly workerInstanceId: string;
}): BridgeWorkerRenderFulfillmentState {
	const fulfillmentIdentity = bridgeWorkerRenderFulfillmentIdentitySchema.parse({
		paneSessionId: props.paneSessionId,
		submissionId: props.submissionId,
		surface: props.surface,
		workerDerivationEpoch: props.workerDerivationEpoch,
		workerInstanceId: props.workerInstanceId,
	});
	return Object.freeze({
		identity: props.identity,
		...fulfillmentIdentity,
		stage: 'desired',
		isDesired: true,
		activeAttempt: null,
		attemptIds: Object.freeze([]),
		closedAttempts: Object.freeze([]),
		retryAtMilliseconds: null,
		paintedResidency: null,
		acceptedUiIntentRevision: null,
	});
}

export function reduceBridgeWorkerRenderFulfillment(
	state: BridgeWorkerRenderFulfillmentState,
	event: BridgeWorkerRenderFulfillmentEvent,
): BridgeWorkerRenderFulfillmentState {
	switch (event.kind) {
		case 'preparation.started':
			assertStage(state, 'desired', event.kind);
			return updateState(state, { stage: 'preparing' });
		case 'publication.started':
			return startPublication(state, event);
		case 'render.disposition':
			return applyRenderDisposition(state, bridgeWorkerRenderDispositionReceiptSchema.parse(event));
		case 'receiptLease.expired':
			return expireReceiptLease(state, bridgeWorkerReceiptLeaseExpiredSchema.parse(event));
		case 'retry.ready':
			return releaseRetry(state, event);
		case 'selection.accepted':
			return acceptPaintedSelection(state, bridgeWorkerSelectionAcceptedReceiptSchema.parse(event));
	}
	return assertNever(event);
}

function startPublication(
	state: BridgeWorkerRenderFulfillmentState,
	event: Extract<BridgeWorkerRenderFulfillmentEvent, { kind: 'publication.started' }>,
): BridgeWorkerRenderFulfillmentState {
	assertStage(state, 'preparing', event.kind);
	bridgeProductIdentifierSchema.parse(event.attemptId);
	if (state.attemptIds.includes(event.attemptId)) {
		throw new Error('Bridge render publication requires a fresh attempt id.');
	}
	if (
		!Number.isFinite(event.publishedAtMilliseconds) ||
		event.publishedAtMilliseconds < 0 ||
		!Number.isFinite(event.receiptLeaseExpiresAtMilliseconds) ||
		event.receiptLeaseExpiresAtMilliseconds <= event.publishedAtMilliseconds
	) {
		throw new Error('Bridge render publication requires a bounded future receipt lease.');
	}
	return updateState(state, {
		stage: 'published',
		activeAttempt: Object.freeze({
			attemptId: event.attemptId,
			receiptLeaseExpiresAtMilliseconds: event.receiptLeaseExpiresAtMilliseconds,
			highestDisposition: null,
		}),
		attemptIds: Object.freeze([...state.attemptIds, event.attemptId]),
		retryAtMilliseconds: null,
	});
}

function applyRenderDisposition(
	state: BridgeWorkerRenderFulfillmentState,
	event: Extract<BridgeWorkerRenderFulfillmentEvent, { kind: 'render.disposition' }>,
): BridgeWorkerRenderFulfillmentState {
	assertRenderReceiptIdentity(state, event);
	const matchingClosedAttempt = state.closedAttempts.find(
		(attempt) => attempt.attemptId === event.attemptId,
	);
	if (matchingClosedAttempt !== undefined) {
		const matchingReason = 'reason' in matchingClosedAttempt ? matchingClosedAttempt.reason : null;
		const eventReason = 'reason' in event ? event.reason : null;
		if (matchingClosedAttempt.disposition === event.disposition && matchingReason === eventReason) {
			return state;
		}
		throw new Error('Bridge render attempt received a conflicting terminal disposition.');
	}
	const activeAttempt = state.activeAttempt;
	if (activeAttempt === null || activeAttempt.attemptId !== event.attemptId) {
		throw new Error('Bridge render disposition does not match the active attempt.');
	}

	if (event.disposition === 'rejected' || event.disposition === 'superseded') {
		const retryAtMilliseconds = requiredRetryAt(event);
		return closeForRetry(state, {
			attemptId: event.attemptId,
			disposition: event.disposition,
			reason: event.reason,
			retryAtMilliseconds,
		});
	}
	const expectedDisposition =
		activeAttempt.highestDisposition === null
			? 'queued'
			: activeAttempt.highestDisposition === 'queued'
				? 'applied'
				: 'painted';
	if (event.disposition === activeAttempt.highestDisposition) {
		return state;
	}
	if (event.disposition !== expectedDisposition) {
		throw new Error(
			`Bridge render disposition is out of order: expected ${expectedDisposition}, received ${event.disposition}.`,
		);
	}
	if (event.disposition === 'painted') {
		return updateState(state, {
			stage: 'painted',
			isDesired: false,
			activeAttempt: null,
			closedAttempts: Object.freeze([
				...state.closedAttempts,
				Object.freeze({ attemptId: event.attemptId, disposition: 'painted' as const }),
			]),
			paintedResidency: Object.freeze({
				attemptId: event.attemptId,
				paneSessionId: state.paneSessionId,
				submissionId: state.submissionId,
				surface: state.surface,
				windowKey: state.identity.windowKey,
				workerDerivationEpoch: state.workerDerivationEpoch,
				workerInstanceId: state.workerInstanceId,
			}),
		});
	}
	return updateState(state, {
		stage: event.disposition,
		activeAttempt: Object.freeze({
			...activeAttempt,
			highestDisposition: event.disposition,
		}),
	});
}

function expireReceiptLease(
	state: BridgeWorkerRenderFulfillmentState,
	event: Extract<BridgeWorkerRenderFulfillmentEvent, { kind: 'receiptLease.expired' }>,
): BridgeWorkerRenderFulfillmentState {
	assertRenderReceiptIdentity(state, event);
	const activeAttempt = state.activeAttempt;
	if (activeAttempt === null || activeAttempt.attemptId !== event.attemptId) {
		throw new Error('Bridge receipt lease expiration does not match the active attempt.');
	}
	if (event.atMilliseconds < activeAttempt.receiptLeaseExpiresAtMilliseconds) {
		throw new Error('Bridge receipt lease cannot expire before its deadline.');
	}
	if (event.retryAtMilliseconds < event.atMilliseconds) {
		throw new Error('Bridge receipt retry cannot precede lease expiration.');
	}
	return closeForRetry(state, {
		attemptId: event.attemptId,
		disposition: 'lease_expired',
		retryAtMilliseconds: event.retryAtMilliseconds,
	});
}

function releaseRetry(
	state: BridgeWorkerRenderFulfillmentState,
	event: Extract<BridgeWorkerRenderFulfillmentEvent, { kind: 'retry.ready' }>,
): BridgeWorkerRenderFulfillmentState {
	assertStage(state, 'retry_wait', event.kind);
	if (state.retryAtMilliseconds === null || event.atMilliseconds < state.retryAtMilliseconds) {
		throw new Error('Bridge render retry is still inside its bounded backoff.');
	}
	return updateState(state, {
		stage: 'desired',
		activeAttempt: null,
		retryAtMilliseconds: null,
	});
}

function acceptPaintedSelection(
	state: BridgeWorkerRenderFulfillmentState,
	event: Extract<BridgeWorkerRenderFulfillmentEvent, { kind: 'selection.accepted' }>,
): BridgeWorkerRenderFulfillmentState {
	assertRenderReceiptIdentity(state, event);
	assertStage(state, 'painted', event.kind);
	if (state.paintedResidency === null || state.paintedResidency.attemptId !== event.attemptId) {
		throw new Error('Bridge selection acceptance requires matching painted residency.');
	}
	if (event.atMilliseconds >= event.validationLeaseExpiresAtMilliseconds) {
		throw new Error('Bridge selection acceptance requires a current validation lease.');
	}
	if (
		state.acceptedUiIntentRevision !== null &&
		event.uiIntentRevision <= state.acceptedUiIntentRevision
	) {
		throw new Error('Bridge selection UI intent revision must advance monotonically.');
	}
	return updateState(state, { acceptedUiIntentRevision: event.uiIntentRevision });
}

function assertRenderReceiptIdentity(
	state: BridgeWorkerRenderFulfillmentState,
	event: BridgeWorkerRenderReceiptTransition,
): void {
	if (
		event.paneSessionId !== state.paneSessionId ||
		event.workerInstanceId !== state.workerInstanceId ||
		event.surface !== state.surface ||
		event.workerDerivationEpoch !== state.workerDerivationEpoch
	) {
		throw new Error('Bridge render receipt context does not match current fulfillment.');
	}
	if (event.submissionId !== state.submissionId) {
		throw new Error(
			'Bridge render receipt submission identity does not match current fulfillment.',
		);
	}
	if (event.windowKey !== state.identity.windowKey) {
		throw new Error('Bridge render receipt window identity does not match current fulfillment.');
	}
	if (event.kind !== 'render.disposition') {
		return;
	}
	if (!Number.isFinite(event.receivedAtMilliseconds)) {
		throw new Error('Bridge render disposition requires a finite receive timestamp.');
	}
	if (
		event.receivedAtMilliseconds < 0 ||
		(state.activeAttempt !== null &&
			event.receivedAtMilliseconds > state.activeAttempt.receiptLeaseExpiresAtMilliseconds)
	) {
		throw new Error('Bridge render disposition arrived outside its receipt lease.');
	}
}

function closeForRetry(
	state: BridgeWorkerRenderFulfillmentState,
	props:
		| {
				readonly attemptId: string;
				readonly disposition: 'lease_expired';
				readonly retryAtMilliseconds: number;
		  }
		| {
				readonly attemptId: string;
				readonly disposition: 'rejected' | 'superseded';
				readonly reason: BridgeWorkerRenderRejectionReason;
				readonly retryAtMilliseconds: number;
		  },
): BridgeWorkerRenderFulfillmentState {
	const closedAttempt: BridgeWorkerClosedRenderAttempt =
		props.disposition === 'lease_expired'
			? Object.freeze({ attemptId: props.attemptId, disposition: props.disposition })
			: Object.freeze({
					attemptId: props.attemptId,
					disposition: props.disposition,
					reason: props.reason,
				});
	return updateState(state, {
		stage: 'retry_wait',
		isDesired: true,
		activeAttempt: null,
		closedAttempts: Object.freeze([...state.closedAttempts, closedAttempt]),
		retryAtMilliseconds: props.retryAtMilliseconds,
	});
}

function requiredRetryAt(
	event: Extract<BridgeWorkerRenderDispositionReceipt, { disposition: 'rejected' | 'superseded' }>,
): number {
	if (event.retryAtMilliseconds < event.receivedAtMilliseconds) {
		throw new Error('Bridge rejected render disposition requires bounded retry timing.');
	}
	return event.retryAtMilliseconds;
}

function assertStage(
	state: BridgeWorkerRenderFulfillmentState,
	expectedStage: BridgeWorkerRenderFulfillmentStage,
	eventKind: BridgeWorkerRenderFulfillmentEvent['kind'],
): void {
	if (state.stage !== expectedStage) {
		throw new Error(
			`Bridge render event ${eventKind} requires ${expectedStage}, received ${state.stage}.`,
		);
	}
}

function updateState(
	state: BridgeWorkerRenderFulfillmentState,
	patch: Partial<BridgeWorkerRenderFulfillmentState>,
): BridgeWorkerRenderFulfillmentState {
	return Object.freeze({ ...state, ...patch });
}

export type BridgeWorkerContentAvailability =
	| 'absent'
	| 'loading'
	| 'ready'
	| 'unavailable'
	| 'failed';

export interface BridgeWorkerContentAvailabilityState {
	readonly identity: BridgeWorkerSemanticWindowIdentity;
	readonly state: BridgeWorkerContentAvailability;
}

export function reduceBridgeWorkerContentAvailability(
	current: BridgeWorkerContentAvailabilityState | null,
	next: BridgeWorkerContentAvailabilityState,
): BridgeWorkerContentAvailabilityState {
	if (current === null || current.identity.windowKey !== next.identity.windowKey) {
		return Object.freeze(next);
	}
	if (current.state === next.state) {
		return current;
	}
	if (availabilityRank(next.state) < availabilityRank(current.state)) {
		throw new Error(
			`Bridge content availability cannot transition ${current.state} to ${next.state} for one semantic window identity.`,
		);
	}
	if (availabilityRank(current.state) === 2) {
		throw new Error(
			`Bridge content availability cannot leave terminal ${current.state} for one semantic window identity.`,
		);
	}
	return Object.freeze(next);
}

function availabilityRank(availability: BridgeWorkerContentAvailability): number {
	switch (availability) {
		case 'absent':
			return 0;
		case 'loading':
			return 1;
		case 'ready':
		case 'unavailable':
		case 'failed':
			return 2;
	}
	return assertNever(availability);
}

function assertNever(value: never): never {
	throw new Error(`Unexpected Bridge render fulfillment variant: ${String(value)}.`);
}
