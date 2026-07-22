import { BRIDGE_PRODUCT_MAXIMUM_ACTIVE_SUBSCRIPTION_COUNT } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	bridgeProductControlResponseSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionEvent } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import type {
	BridgeProductDevSubscriptionFrameIdentity,
	BridgeProductDevSubscriptionFramePayload,
} from './bridge-product-dev-metadata-writer.js';
import {
	bridgeProductDevControlIdentity,
	bridgeProductDevInterestHash,
	bridgeProductDevInterestState,
	bridgeProductDevRequestError,
	emptyBridgeProductDevInterestState,
	type BridgeProductDevFileSubscription,
	type BridgeProductDevReviewSubscription,
	type BridgeProductDevSession,
	type BridgeProductDevSubscription,
} from './bridge-product-dev-session.js';

type BridgeProductDevSubscriptionControlRequest = Extract<
	BridgeProductControlRequest,
	{
		readonly kind: 'subscription.cancel' | 'subscription.open' | 'subscription.updateBatch';
	}
>;

export async function handleBridgeProductDevSubscriptionControl(
	session: BridgeProductDevSession,
	request: BridgeProductDevSubscriptionControlRequest,
): Promise<BridgeProductControlResponse> {
	switch (request.kind) {
		case 'subscription.open':
			return await openSubscription(session, request);
		case 'subscription.updateBatch':
			return updateSubscription(session, request);
		case 'subscription.cancel':
			return cancelSubscription(session, request);
	}
	throw new Error('Bridge product dev subscription request kind is unsupported.');
}

async function openSubscription(
	session: BridgeProductDevSession,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.open' }>,
): Promise<BridgeProductControlResponse> {
	if (
		session.metadataWriter === null ||
		session.subscriptionsById.has(request.subscriptionId) ||
		session.subscriptionsById.size >= BRIDGE_PRODUCT_MAXIMUM_ACTIVE_SUBSCRIPTION_COUNT
	) {
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'unsupported_subscription',
		);
	}
	const subscription = await makeSubscription(session, request);
	if (subscription === null) {
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'invalid_request',
		);
	}
	session.subscriptionsById.set(subscription.subscriptionId, subscription);
	void publishInitialSubscription(session, subscription).catch((): void => {
		closeMetadataWriterAfterFailure(session);
	});
	return bridgeProductControlResponseSchema.parse({
		...bridgeProductDevControlIdentity(request),
		interestRevision: 0,
		interestSha256: subscription.interestHash,
		kind: 'subscription.openAccepted',
		subscriptionId: subscription.subscriptionId,
		subscriptionKind: subscription.subscriptionKind,
	});
}

async function makeSubscription(
	session: BridgeProductDevSession,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.open' }>,
): Promise<BridgeProductDevSubscription | null> {
	const emptyState = emptyBridgeProductDevInterestState(request.subscription.subscriptionKind);
	const common = {
		interestHash: bridgeProductDevInterestHash(emptyState),
		interestRevision: 0,
		sequence: 0,
		subscriptionId: request.subscriptionId,
		workerDerivationEpoch: request.workerDerivationEpoch,
	};
	if (request.subscription.subscriptionKind === 'file.metadata') {
		session.fileSource ??= await (await session.loadFileAdapter()).loadSource();
		if (
			JSON.stringify(request.subscription.source) !==
			JSON.stringify(session.fileSource.configuration)
		) {
			return null;
		}
		return {
			...common,
			interestLanesByPath: new Map(),
			pathScope: new Set(),
			sourceCursor: session.fileSource.identity.sourceCursor,
			sourceGeneration: session.fileSource.identity.subscriptionGeneration,
			subscriptionKind: 'file.metadata',
		};
	}
	session.reviewSource ??= await (
		await session.loadReviewAdapter()
	).loadSource(session.abortController.signal);
	return {
		...common,
		interestLanesByItemId: new Map(),
		sourceCursor: session.reviewSource.cursor,
		sourceGeneration: session.reviewSource.generation,
		subscriptionKind: 'review.metadata',
	};
}

function updateSubscription(
	session: BridgeProductDevSession,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.updateBatch' }>,
): BridgeProductControlResponse {
	const subscription = session.subscriptionsById.get(request.subscriptionId);
	if (!updateMatchesSubscription(subscription, request)) {
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'invalid_request',
		);
	}
	const targetState = targetInterestState(subscription, request);
	const targetHash = bridgeProductDevInterestHash(targetState.state);
	if (targetHash !== request.targetInterestSha256) {
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'invalid_request',
		);
	}
	targetState.commit();
	subscription.interestRevision = request.targetInterestRevision;
	subscription.interestHash = targetHash;
	void publishSubscriptionUpdate(session, subscription, request).catch((): void => {
		closeMetadataWriterAfterFailure(session);
	});
	return bridgeProductControlResponseSchema.parse({
		...bridgeProductDevControlIdentity(request),
		batchIndex: 0,
		disposition: 'committed',
		kind: 'subscription.updateBatchAccepted',
		subscriptionId: subscription.subscriptionId,
		subscriptionKind: subscription.subscriptionKind,
		targetInterestRevision: request.targetInterestRevision,
		targetInterestSha256: targetHash,
		updateId: request.updateId,
	});
}

function cancelSubscription(
	session: BridgeProductDevSession,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.cancel' }>,
): BridgeProductControlResponse {
	const subscription = session.subscriptionsById.get(request.subscriptionId);
	if (
		subscription === undefined ||
		request.subscriptionKind !== subscription.subscriptionKind ||
		request.workerDerivationEpoch !== subscription.workerDerivationEpoch
	) {
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'invalid_request',
		);
	}
	session.subscriptionsById.delete(subscription.subscriptionId);
	void writeSubscriptionFrame(session, subscription, {
		kind: 'subscription.cancelled',
	}).catch((): void => {
		closeMetadataWriterAfterFailure(session);
	});
	return bridgeProductControlResponseSchema.parse({
		...bridgeProductDevControlIdentity(request),
		kind: 'subscription.cancelAccepted',
		subscriptionId: subscription.subscriptionId,
		subscriptionKind: subscription.subscriptionKind,
	});
}

async function publishInitialSubscription(
	session: BridgeProductDevSession,
	subscription: BridgeProductDevSubscription,
): Promise<void> {
	await writeSubscriptionFrame(session, subscription, { kind: 'subscription.accepted' });
	if (subscription.subscriptionKind === 'file.metadata') {
		const source = session.fileSource;
		if (source === null) throw new Error('Bridge product dev File source is unavailable.');
		await writeFileSubscriptionData(session, subscription, {
			eventKind: 'file.sourceAccepted',
			source: source.identity,
		});
		for (const event of source.treeEvents) {
			// oxlint-disable-next-line no-await-in-loop -- Metadata frames preserve source order and pacing.
			await writeFileSubscriptionData(session, subscription, event);
		}
		return;
	}
	const source = session.reviewSource;
	if (source === null) throw new Error('Bridge product dev Review source is unavailable.');
	for (const event of source.events) {
		// oxlint-disable-next-line no-await-in-loop -- Metadata frames preserve source order and pacing.
		await writeReviewSubscriptionData(session, subscription, event);
	}
}

async function publishSubscriptionUpdate(
	session: BridgeProductDevSession,
	subscription: BridgeProductDevSubscription,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.updateBatch' }>,
): Promise<void> {
	await writeSubscriptionFrame(session, subscription, {
		kind: 'subscription.interestsCommitted',
		updateId: request.updateId,
	});
	if (
		subscription.subscriptionKind !== 'file.metadata' ||
		request.delta.subscriptionKind !== 'file.metadata'
	) {
		return;
	}
	for (const addition of request.delta.add) {
		// oxlint-disable-next-line no-await-in-loop -- Descriptor loads preserve demand order and pacing.
		const descriptorEvent = await (await session.loadFileAdapter()).loadDescriptor(addition.path);
		if (session.subscriptionsById.get(subscription.subscriptionId) !== subscription) return;
		// oxlint-disable-next-line no-await-in-loop -- Descriptor frames preserve demand order and pacing.
		await writeFileSubscriptionData(session, subscription, descriptorEvent);
	}
}

function writeFileSubscriptionData(
	session: BridgeProductDevSession,
	subscription: BridgeProductDevFileSubscription,
	event: BridgeProductSubscriptionEvent<'file.metadata'>,
): Promise<void> {
	return writeSubscriptionFrame(session, subscription, {
		data: { event, subscriptionKind: 'file.metadata' },
		kind: 'subscription.data',
	});
}

function writeReviewSubscriptionData(
	session: BridgeProductDevSession,
	subscription: BridgeProductDevReviewSubscription,
	event: BridgeProductSubscriptionEvent<'review.metadata'>,
): Promise<void> {
	return writeSubscriptionFrame(session, subscription, {
		data: { event, subscriptionKind: 'review.metadata' },
		kind: 'subscription.data',
	});
}

function writeSubscriptionFrame(
	session: BridgeProductDevSession,
	subscription: BridgeProductDevSubscription,
	frame: BridgeProductDevSubscriptionFramePayload,
): Promise<void> {
	const writer = session.metadataWriter;
	if (writer === null || writer.response.destroyed) {
		return Promise.reject(new Error('Bridge product dev metadata stream is unavailable.'));
	}
	return writer.writeSubscriptionFrame(
		subscriptionFrameIdentity(subscription),
		subscription,
		frame,
	);
}

function subscriptionFrameIdentity(
	subscription: BridgeProductDevSubscription,
): BridgeProductDevSubscriptionFrameIdentity {
	return {
		cursor: subscription.sourceCursor,
		interestRevision: subscription.interestRevision,
		interestSha256: subscription.interestHash,
		sourceGeneration: subscription.sourceGeneration,
		subscriptionId: subscription.subscriptionId,
		subscriptionKind: subscription.subscriptionKind,
		workerDerivationEpoch: subscription.workerDerivationEpoch,
	};
}

function updateMatchesSubscription(
	subscription: BridgeProductDevSubscription | undefined,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.updateBatch' }>,
): subscription is BridgeProductDevSubscription {
	return (
		subscription !== undefined &&
		request.subscriptionKind === subscription.subscriptionKind &&
		request.delta.subscriptionKind === subscription.subscriptionKind &&
		request.workerDerivationEpoch === subscription.workerDerivationEpoch &&
		request.batchCount === 1 &&
		request.batchIndex === 0 &&
		request.baseInterestRevision === subscription.interestRevision &&
		request.baseInterestSha256 === subscription.interestHash &&
		request.targetInterestRevision === subscription.interestRevision + 1
	);
}

function targetInterestState(
	subscription: BridgeProductDevSubscription,
	request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.updateBatch' }>,
): {
	readonly commit: () => void;
	readonly state: ReturnType<typeof bridgeProductDevInterestState>;
} {
	if (
		subscription.subscriptionKind === 'file.metadata' &&
		request.delta.subscriptionKind === 'file.metadata'
	) {
		const interestLanesByPath = new Map(subscription.interestLanesByPath);
		const pathScope = new Set(subscription.pathScope);
		for (const path of request.delta.removePaths) interestLanesByPath.delete(path);
		for (const addition of request.delta.add) interestLanesByPath.set(addition.path, addition.lane);
		for (const path of request.delta.removePathScope) pathScope.delete(path);
		for (const path of request.delta.addPathScope) pathScope.add(path);
		const candidate: BridgeProductDevFileSubscription = {
			...subscription,
			interestLanesByPath,
			pathScope,
		};
		return {
			commit: (): void => {
				replaceMap(subscription.interestLanesByPath, interestLanesByPath);
				replaceSet(subscription.pathScope, pathScope);
			},
			state: bridgeProductDevInterestState(candidate),
		};
	}
	if (
		subscription.subscriptionKind === 'review.metadata' &&
		request.delta.subscriptionKind === 'review.metadata'
	) {
		const interestLanesByItemId = new Map(subscription.interestLanesByItemId);
		for (const itemId of request.delta.removeItemIds) interestLanesByItemId.delete(itemId);
		for (const addition of request.delta.add) {
			interestLanesByItemId.set(addition.itemId, addition.lane);
		}
		const candidate: BridgeProductDevReviewSubscription = {
			...subscription,
			interestLanesByItemId,
		};
		return {
			commit: (): void => replaceMap(subscription.interestLanesByItemId, interestLanesByItemId),
			state: bridgeProductDevInterestState(candidate),
		};
	}
	throw new Error('Bridge product dev subscription update crossed product kinds.');
}

function closeMetadataWriterAfterFailure(session: BridgeProductDevSession): void {
	session.metadataWriter?.end();
}

function replaceMap<TKey, TValue>(
	target: Map<TKey, TValue>,
	source: ReadonlyMap<TKey, TValue>,
): void {
	target.clear();
	for (const [key, value] of source) target.set(key, value);
}

function replaceSet<TValue>(target: Set<TValue>, source: ReadonlySet<TValue>): void {
	target.clear();
	for (const value of source) target.add(value);
}
