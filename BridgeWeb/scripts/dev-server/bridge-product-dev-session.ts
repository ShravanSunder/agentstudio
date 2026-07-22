import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';

import type { BridgeProductContentRequest } from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import {
	assertBridgeProductResyncReconciliationMatchesRequest,
	bridgeProductMetadataAcceptedStreamSequence,
	bridgeProductControlResponseSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductMetadataStreamRequest,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-interest-state-codec.js';
import type { BridgeDemandLane } from '../../src/core/models/bridge-demand-models.js';
import type { BridgeProductDevContentProducer } from './bridge-product-dev-content-producer.js';
import type {
	BridgeProductDevFileAdapter,
	BridgeProductDevFileSourceSnapshot,
} from './bridge-product-dev-file-adapter.js';
import type { BridgeProductDevWritableResponse } from './bridge-product-dev-http.js';
import { BridgeProductDevMetadataWriter } from './bridge-product-dev-metadata-writer.js';
import type {
	BridgeProductDevReviewAdapterPort,
	BridgeProductDevReviewSourceSnapshot,
} from './bridge-product-dev-review-adapter.js';

interface BridgeProductDevSubscriptionBase {
	interestHash: string;
	interestRevision: number;
	sequence: number;
	readonly sourceCursor: string | null;
	readonly sourceGeneration: number;
	readonly subscriptionId: string;
	readonly workerDerivationEpoch: number;
}

export interface BridgeProductDevFileSubscription extends BridgeProductDevSubscriptionBase {
	readonly interestLanesByPath: Map<string, BridgeDemandLane>;
	readonly pathScope: Set<string>;
	readonly subscriptionKind: 'file.metadata';
}

export interface BridgeProductDevReviewSubscription extends BridgeProductDevSubscriptionBase {
	readonly interestLanesByItemId: Map<string, BridgeDemandLane>;
	readonly subscriptionKind: 'review.metadata';
}

export type BridgeProductDevSubscription =
	| BridgeProductDevFileSubscription
	| BridgeProductDevReviewSubscription;

export interface BridgeProductDevSession {
	readonly abortController: AbortController;
	awaitingResync: boolean;
	cachedRequestBody: Uint8Array;
	cachedResponseBody: Uint8Array;
	readonly capability: string;
	readonly contentProducersByRequestId: Map<string, BridgeProductDevContentProducer>;
	fileSource: BridgeProductDevFileSourceSnapshot | null;
	lastAcceptedRequestSequence: number;
	lastClosedMetadataStreamSequence: number | null;
	readonly loadFileAdapter: () => Promise<BridgeProductDevFileAdapter>;
	readonly loadReviewAdapter: () => Promise<BridgeProductDevReviewAdapterPort>;
	metadataWriter: BridgeProductDevMetadataWriter | null;
	readonly paneSessionId: string;
	pendingControl: Promise<void>;
	resyncResumeFromStreamSequence: number | null;
	reviewSource: BridgeProductDevReviewSourceSnapshot | null;
	readonly subscriptionsById: Map<string, BridgeProductDevSubscription>;
	readonly workerInstanceId: string;
}

export function bridgeProductDevRequestMatchesSession(
	request: Pick<
		BridgeProductControlRequest | BridgeProductContentRequest,
		'paneSessionId' | 'workerInstanceId'
	>,
	session: BridgeProductDevSession,
): boolean {
	return (
		request.paneSessionId === session.paneSessionId &&
		request.workerInstanceId === session.workerInstanceId
	);
}

export function isBridgeProductDevExactRetry(
	session: BridgeProductDevSession,
	request: BridgeProductControlRequest,
	body: Uint8Array,
): boolean {
	return (
		request.requestSequence === session.lastAcceptedRequestSequence &&
		Buffer.from(body).equals(Buffer.from(session.cachedRequestBody))
	);
}

export function bridgeProductDevControlIdentity(request: BridgeProductControlRequest): {
	readonly paneSessionId: string;
	readonly requestId: string;
	readonly requestSequence: number;
	readonly wireVersion: 2;
	readonly workerInstanceId: string;
} {
	return {
		paneSessionId: request.paneSessionId,
		requestId: request.requestId,
		requestSequence: request.requestSequence,
		wireVersion: request.wireVersion,
		workerInstanceId: request.workerInstanceId,
	};
}

export function bridgeProductDevRequestError(
	request: BridgeProductControlRequest,
	nextExpectedRequestSequence: number,
	code: Extract<BridgeProductControlResponse, { readonly kind: 'request.error' }>['code'],
): BridgeProductControlResponse {
	return bridgeProductControlResponseSchema.parse({
		...bridgeProductDevControlIdentity(request),
		code,
		kind: 'request.error',
		nextExpectedRequestSequence,
		retryAfterMilliseconds: null,
		retryable: false,
		safeMessage: null,
	});
}

export function openBridgeProductDevMetadataWriter(props: {
	readonly request: BridgeProductMetadataStreamRequest;
	readonly response: BridgeProductDevWritableResponse;
	readonly session: BridgeProductDevSession;
}): BridgeProductDevMetadataWriter | null {
	const isInitialMetadataStream = props.session.lastClosedMetadataStreamSequence === null;
	const hasValidResumePosition = isInitialMetadataStream
		? props.request.resumeFromStreamSequence === null
		: props.request.resumeFromStreamSequence === props.session.lastClosedMetadataStreamSequence;
	if (
		props.request.paneSessionId !== props.session.paneSessionId ||
		props.request.workerInstanceId !== props.session.workerInstanceId ||
		!hasValidResumePosition ||
		props.session.metadataWriter !== null
	) {
		return null;
	}
	const metadataWriter = new BridgeProductDevMetadataWriter({
		initialStreamSequence: bridgeProductMetadataAcceptedStreamSequence(props.request),
		metadataStreamId: props.request.metadataStreamId,
		paneSessionId: props.session.paneSessionId,
		response: props.response,
		workerInstanceId: props.session.workerInstanceId,
	});
	props.session.metadataWriter = metadataWriter;
	if (props.request.resumeFromStreamSequence !== null) {
		props.session.awaitingResync = true;
		props.session.resyncResumeFromStreamSequence = props.request.resumeFromStreamSequence;
	}
	props.response.once('close', (): void => {
		metadataWriter.cancel();
		if (metadataWriter.streamSequence >= 0) {
			props.session.lastClosedMetadataStreamSequence = metadataWriter.streamSequence;
		}
		if (props.session.metadataWriter === metadataWriter) props.session.metadataWriter = null;
		for (const producer of props.session.contentProducersByRequestId.values()) producer.cancel();
		props.session.contentProducersByRequestId.clear();
		props.session.subscriptionsById.clear();
	});
	return metadataWriter;
}

export function reconcileBridgeProductDevSession(
	session: BridgeProductDevSession,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'workerSession.resync' }>,
): BridgeProductControlResponse {
	const metadataWriter = session.metadataWriter;
	if (
		!session.awaitingResync ||
		metadataWriter === null ||
		request.lastAcceptedRequestSequence !== session.lastAcceptedRequestSequence ||
		request.lastAcceptedStreamSequence !== session.resyncResumeFromStreamSequence
	) {
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'resync_required',
		);
	}
	const response = bridgeProductControlResponseSchema.parse({
		...bridgeProductDevControlIdentity(request),
		kind: 'resync.accepted',
		metadataStreamSequenceBarrier: metadataWriter.streamSequence,
		nextExpectedRequestSequence: request.requestSequence + 1,
		reconciliation: request.activeSubscriptions.map((activeSubscription) => ({
			disposition: 'reopenRequired' as const,
			reason: 'snapshot_required' as const,
			requiredWorkerDerivationEpoch: activeSubscription.workerDerivationEpoch,
			subscriptionId: activeSubscription.subscriptionId,
			subscriptionKind: activeSubscription.subscriptionKind,
		})),
	});
	assertBridgeProductResyncReconciliationMatchesRequest({ request, response });
	session.subscriptionsById.clear();
	session.awaitingResync = false;
	session.resyncResumeFromStreamSequence = null;
	return response;
}

export function emptyBridgeProductDevInterestState(
	subscriptionKind: BridgeProductDevSubscription['subscriptionKind'],
): BridgeProductSubscriptionInterestState {
	return subscriptionKind === 'file.metadata'
		? { interests: [], pathScope: [], subscriptionKind }
		: { interests: [], subscriptionKind };
}

export function bridgeProductDevInterestState(
	subscription: BridgeProductDevSubscription,
): BridgeProductSubscriptionInterestState {
	if (subscription.subscriptionKind === 'file.metadata') {
		return {
			interests: groupedIdentitiesByLane(subscription.interestLanesByPath).map(([lane, paths]) => ({
				lane,
				paths,
			})),
			pathScope: [...subscription.pathScope],
			subscriptionKind: subscription.subscriptionKind,
		};
	}
	return {
		interests: groupedIdentitiesByLane(subscription.interestLanesByItemId).map(
			([lane, itemIds]) => ({ itemIds, lane }),
		),
		subscriptionKind: subscription.subscriptionKind,
	};
}

export function bridgeProductDevInterestHash(
	state: BridgeProductSubscriptionInterestState,
): string {
	return createHash('sha256')
		.update(encodeBridgeProductSubscriptionInterestState(state))
		.digest('hex');
}

export function retireBridgeProductDevSession(session: BridgeProductDevSession): void {
	session.abortController.abort();
	session.metadataWriter?.end();
	session.metadataWriter = null;
	for (const producer of session.contentProducersByRequestId.values()) producer.cancel();
	session.contentProducersByRequestId.clear();
	session.subscriptionsById.clear();
}

function groupedIdentitiesByLane(
	interestLanesByIdentity: ReadonlyMap<string, BridgeDemandLane>,
): readonly (readonly [lane: BridgeDemandLane, identities: readonly string[]])[] {
	const identitiesByLane = new Map<BridgeDemandLane, string[]>();
	for (const [identity, lane] of interestLanesByIdentity) {
		const identities = identitiesByLane.get(lane) ?? [];
		identities.push(identity);
		identitiesByLane.set(lane, identities);
	}
	return [...identitiesByLane];
}
