import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';

import {
	bridgeProductContentIdentityFromDescriptor,
	type BridgeProductContentHeader,
	type BridgeProductContentRequest,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
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
import {
	BridgeProductDevFileAdapter,
	type BridgeProductDevFileSourceSnapshot,
} from './bridge-product-dev-file-adapter.js';
import type { BridgeProductDevWritableResponse } from './bridge-product-dev-http.js';
import { BridgeProductDevMetadataWriter } from './bridge-product-dev-metadata-writer.js';

export interface BridgeProductDevFileSubscription {
	interestHash: string;
	interestRevision: number;
	readonly interestLanesByPath: Map<string, BridgeDemandLane>;
	readonly pathScope: Set<string>;
	sequence: number;
	readonly subscriptionId: string;
	readonly workerDerivationEpoch: number;
}

export interface BridgeProductDevFileSession {
	readonly adapter: BridgeProductDevFileAdapter;
	awaitingResync: boolean;
	cachedRequestBody: Uint8Array;
	cachedResponseBody: Uint8Array;
	lastAcceptedRequestSequence: number;
	lastClosedMetadataStreamSequence: number | null;
	metadataWriter: BridgeProductDevMetadataWriter | null;
	readonly paneSessionId: string;
	source: BridgeProductDevFileSourceSnapshot | null;
	subscription: BridgeProductDevFileSubscription | null;
	resyncResumeFromStreamSequence: number | null;
	readonly workerInstanceId: string;
}

export function bridgeProductDevRequestMatchesSession(
	request: Pick<
		BridgeProductControlRequest | BridgeProductContentRequest,
		'paneSessionId' | 'workerInstanceId'
	>,
	session: BridgeProductDevFileSession,
): boolean {
	return (
		request.paneSessionId === session.paneSessionId &&
		request.workerInstanceId === session.workerInstanceId
	);
}

export function isBridgeProductDevExactRetry(
	session: BridgeProductDevFileSession,
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
	readonly session: BridgeProductDevFileSession;
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
		if (metadataWriter.streamSequence >= 0) {
			props.session.lastClosedMetadataStreamSequence = metadataWriter.streamSequence;
		}
		if (props.session.metadataWriter === metadataWriter) props.session.metadataWriter = null;
	});
	return metadataWriter;
}

export function reconcileBridgeProductDevFileSession(
	session: BridgeProductDevFileSession,
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
	session.subscription = null;
	session.awaitingResync = false;
	session.resyncResumeFromStreamSequence = null;
	return response;
}

export function emptyBridgeProductDevFileInterestState(): Extract<
	BridgeProductSubscriptionInterestState,
	{ readonly subscriptionKind: 'file.metadata' }
> {
	return { interests: [], pathScope: [], subscriptionKind: 'file.metadata' };
}

export function bridgeProductDevFileInterestState(subscription: {
	readonly interestLanesByPath: ReadonlyMap<string, BridgeDemandLane>;
	readonly pathScope: ReadonlySet<string>;
}): Extract<
	BridgeProductSubscriptionInterestState,
	{ readonly subscriptionKind: 'file.metadata' }
> {
	const pathsByLane = new Map<BridgeDemandLane, string[]>();
	for (const [path, lane] of subscription.interestLanesByPath) {
		const paths = pathsByLane.get(lane) ?? [];
		paths.push(path);
		pathsByLane.set(lane, paths);
	}
	return {
		interests: [...pathsByLane].map(([lane, paths]) => ({ lane, paths })),
		pathScope: [...subscription.pathScope],
		subscriptionKind: 'file.metadata',
	};
}

export function bridgeProductDevInterestHash(
	state: BridgeProductSubscriptionInterestState,
): string {
	return createHash('sha256')
		.update(encodeBridgeProductSubscriptionInterestState(state))
		.digest('hex');
}

export function bridgeProductDevContentAcceptedHeader(
	request: Extract<BridgeProductContentRequest, { readonly contentKind: 'file.content' }>,
): Extract<BridgeProductContentHeader, { readonly kind: 'content.accepted' }> {
	return {
		contentRequestId: request.contentRequestId,
		contentSequence: 0 as const,
		declaredByteLength: request.descriptor.declaredByteLength,
		expectedSha256: request.descriptor.expectedSha256,
		identity: bridgeProductContentIdentityFromDescriptor(request.descriptor),
		kind: 'content.accepted' as const,
		leaseId: request.leaseId,
		maximumBytes: request.descriptor.maximumBytes,
		paneSessionId: request.paneSessionId,
		wireVersion: request.wireVersion,
		workerDerivationEpoch: request.workerDerivationEpoch,
		workerInstanceId: request.workerInstanceId,
	};
}
