import { z } from 'zod';

import type { BridgeDemandLane } from '../models/bridge-demand-models.js';
import {
	bridgeProductUnicodeScalarUtf8ByteLength,
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
} from './bridge-product-contract-primitives.js';
import {
	type BridgeProductMetadataApplicationInterestStateEncodingPreflight,
	defineBridgeProductMetadataApplicationProtocol,
	BridgeProductMetadataApplicationRegistry,
	registerBridgeProductMetadataApplicationProtocol,
} from './bridge-product-metadata-application-protocol.js';
import {
	bridgeProductControlRequestSchema,
	type BridgeProductControlRequest,
} from './bridge-product-session-contracts.js';
import {
	bridgeProductAnnotationSubscriptionOptionsSchema,
	bridgeProductAnnotationSubscriptionUpdateOptionsSchema,
	bridgeProductFileAnnotationSubscriptionDataSchema,
	bridgeProductFileMetadataInterestDeltaSchema,
	bridgeProductFileMetadataSubscriptionDataSchema,
	bridgeProductFileMetadataSubscriptionOptionsSchema,
	bridgeProductFileMetadataSubscriptionUpdateOptionsSchema,
	bridgeProductReviewAnnotationSubscriptionDataSchema,
	bridgeProductReviewMetadataInterestDeltaSchema,
	bridgeProductReviewMetadataSubscriptionDataSchema,
	bridgeProductReviewMetadataSubscriptionOptionsSchema,
	bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema,
} from './bridge-product-subscription-contracts.js';

const fileAnnotationOpenSchema = z
	.object({ subscriptionKind: z.literal('file.annotations') })
	.strict();
const fileAnnotationInterestStateSchema = fileAnnotationOpenSchema;
const fileAnnotationInterestDeltaSchema = fileAnnotationOpenSchema;
const reviewAnnotationOpenSchema = z
	.object({ subscriptionKind: z.literal('review.annotations') })
	.strict();
const reviewAnnotationInterestStateSchema = reviewAnnotationOpenSchema;
const reviewAnnotationInterestDeltaSchema = reviewAnnotationOpenSchema;

const fileMetadataOpenSchema = z
	.object({
		source: bridgeProductFileMetadataSubscriptionOptionsSchema.shape.source,
		subscriptionKind: z.literal('file.metadata'),
	})
	.strict();
const fileMetadataInterestStateSchema =
	bridgeProductFileMetadataSubscriptionUpdateOptionsSchema.safeExtend({
		subscriptionKind: z.literal('file.metadata'),
	});
const fileMetadataInterestStatePreflightSchema = z
	.object({
		...bridgeProductFileMetadataSubscriptionUpdateOptionsSchema.shape,
		subscriptionKind: z.literal('file.metadata'),
	})
	.strict();
const reviewMetadataOpenSchema = z
	.object({ subscriptionKind: z.literal('review.metadata') })
	.strict();
const reviewMetadataInterestStateSchema =
	bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.safeExtend({
		subscriptionKind: z.literal('review.metadata'),
	});
const reviewMetadataInterestStatePreflightSchema = z
	.object({
		...bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.shape,
		subscriptionKind: z.literal('review.metadata'),
	})
	.strict();

type FileMetadataInterestState = z.infer<typeof fileMetadataInterestStateSchema>;
type ReviewMetadataInterestState = z.infer<typeof reviewMetadataInterestStateSchema>;

export const bridgeProductFileAnnotationMetadataApplicationProtocol =
	defineBridgeProductMetadataApplicationProtocol({
		dataSchema: bridgeProductFileAnnotationSubscriptionDataSchema,
		emptyInterestState: () => ({ subscriptionKind: 'file.annotations' }),
		encodeInterestState: () => encodeCanonicalInterestState(3, [], []),
		initialOpen: () => ({ subscriptionKind: 'file.annotations' }),
		initialUpdateOptions: (options) =>
			bridgeProductAnnotationSubscriptionUpdateOptionsSchema.parse(options),
		interestDelta: () => ({ subscriptionKind: 'file.annotations' }),
		interestDeltaItemCount: () => 0,
		interestDeltaSchema: fileAnnotationInterestDeltaSchema,
		interestStatePreflightSchema: fileAnnotationInterestStateSchema,
		interestStateForUpdate: (options) => {
			bridgeProductAnnotationSubscriptionUpdateOptionsSchema.parse(options);
			return { subscriptionKind: 'file.annotations' };
		},
		interestStateSchema: fileAnnotationInterestStateSchema,
		kind: 'file.annotations',
		openSchema: fileAnnotationOpenSchema,
		optionsSchema: bridgeProductAnnotationSubscriptionOptionsSchema,
		preflightInterestState: () => acceptedInterestStatePreflight(6, 0),
		readEventSourceGeneration: (event) => event.sourceGeneration,
		surface: 'file',
		updateOptionsSchema: bridgeProductAnnotationSubscriptionUpdateOptionsSchema,
	});

export const bridgeProductReviewAnnotationMetadataApplicationProtocol =
	defineBridgeProductMetadataApplicationProtocol({
		dataSchema: bridgeProductReviewAnnotationSubscriptionDataSchema,
		emptyInterestState: () => ({ subscriptionKind: 'review.annotations' }),
		encodeInterestState: () => encodeCanonicalInterestState(4, [], []),
		initialOpen: () => ({ subscriptionKind: 'review.annotations' }),
		initialUpdateOptions: (options) =>
			bridgeProductAnnotationSubscriptionUpdateOptionsSchema.parse(options),
		interestDelta: () => ({ subscriptionKind: 'review.annotations' }),
		interestDeltaItemCount: () => 0,
		interestDeltaSchema: reviewAnnotationInterestDeltaSchema,
		interestStatePreflightSchema: reviewAnnotationInterestStateSchema,
		interestStateForUpdate: (options) => {
			bridgeProductAnnotationSubscriptionUpdateOptionsSchema.parse(options);
			return { subscriptionKind: 'review.annotations' };
		},
		interestStateSchema: reviewAnnotationInterestStateSchema,
		kind: 'review.annotations',
		openSchema: reviewAnnotationOpenSchema,
		optionsSchema: bridgeProductAnnotationSubscriptionOptionsSchema,
		preflightInterestState: () => acceptedInterestStatePreflight(6, 0),
		readEventSourceGeneration: (event) => event.sourceGeneration,
		surface: 'review',
		updateOptionsSchema: bridgeProductAnnotationSubscriptionUpdateOptionsSchema,
	});

export const bridgeProductFileMetadataApplicationProtocol =
	defineBridgeProductMetadataApplicationProtocol({
		dataSchema: bridgeProductFileMetadataSubscriptionDataSchema,
		emptyInterestState: () => ({
			interests: [],
			pathScope: [],
			subscriptionKind: 'file.metadata',
		}),
		encodeInterestState: (state) =>
			encodeCanonicalInterestState(2, fileEncodedInterests(state), state.pathScope),
		initialOpen: (options) => ({
			source: bridgeProductFileMetadataSubscriptionOptionsSchema.parse(options).source,
			subscriptionKind: 'file.metadata',
		}),
		initialUpdateOptions: (options) => {
			const parsed = bridgeProductFileMetadataSubscriptionOptionsSchema.parse(options);
			return { interests: parsed.interests, pathScope: parsed.pathScope };
		},
		interestDelta: fileMetadataInterestDelta,
		interestDeltaItemCount: (delta) =>
			delta.add.length +
			delta.addPathScope.length +
			delta.removePathScope.length +
			delta.removePaths.length,
		interestDeltaSchema: bridgeProductFileMetadataInterestDeltaSchema,
		interestStatePreflightSchema: fileMetadataInterestStatePreflightSchema,
		interestStateForUpdate: (options) => ({
			...bridgeProductFileMetadataSubscriptionUpdateOptionsSchema.parse(options),
			subscriptionKind: 'file.metadata',
		}),
		interestStateSchema: fileMetadataInterestStateSchema,
		kind: 'file.metadata',
		openSchema: fileMetadataOpenSchema,
		optionsSchema: bridgeProductFileMetadataSubscriptionOptionsSchema,
		preflightInterestState: fileMetadataInterestStatePreflight,
		readEventSourceGeneration: (event) => event.source.subscriptionGeneration,
		surface: 'file',
		updateOptionsSchema: bridgeProductFileMetadataSubscriptionUpdateOptionsSchema,
	});

export const bridgeProductReviewMetadataApplicationProtocol =
	defineBridgeProductMetadataApplicationProtocol({
		dataSchema: bridgeProductReviewMetadataSubscriptionDataSchema,
		emptyInterestState: () => ({ interests: [], subscriptionKind: 'review.metadata' }),
		encodeInterestState: (state) =>
			encodeCanonicalInterestState(1, reviewEncodedInterests(state), []),
		initialOpen: () => ({ subscriptionKind: 'review.metadata' }),
		initialUpdateOptions: (options) =>
			bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.parse(options),
		interestDelta: reviewMetadataInterestDelta,
		interestDeltaItemCount: (delta) => delta.add.length + delta.removeItemIds.length,
		interestDeltaSchema: bridgeProductReviewMetadataInterestDeltaSchema,
		interestStatePreflightSchema: reviewMetadataInterestStatePreflightSchema,
		interestStateForUpdate: (options) => ({
			...bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.parse(options),
			subscriptionKind: 'review.metadata',
		}),
		interestStateSchema: reviewMetadataInterestStateSchema,
		kind: 'review.metadata',
		openSchema: reviewMetadataOpenSchema,
		optionsSchema: bridgeProductReviewMetadataSubscriptionOptionsSchema,
		preflightInterestState: reviewMetadataInterestStatePreflight,
		readEventSourceGeneration: (event) => event.generation,
		surface: 'review',
		updateOptionsSchema: bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema,
	});

export type BridgeProductRegisteredMetadataApplicationProtocol =
	| typeof bridgeProductFileAnnotationMetadataApplicationProtocol
	| typeof bridgeProductFileMetadataApplicationProtocol
	| typeof bridgeProductReviewAnnotationMetadataApplicationProtocol
	| typeof bridgeProductReviewMetadataApplicationProtocol;

export const bridgeProductMetadataApplicationRegistry =
	new BridgeProductMetadataApplicationRegistry([
		registerBridgeProductMetadataApplicationProtocol(
			bridgeProductFileAnnotationMetadataApplicationProtocol,
		),
		registerBridgeProductMetadataApplicationProtocol(bridgeProductFileMetadataApplicationProtocol),
		registerBridgeProductMetadataApplicationProtocol(
			bridgeProductReviewAnnotationMetadataApplicationProtocol,
		),
		registerBridgeProductMetadataApplicationProtocol(
			bridgeProductReviewMetadataApplicationProtocol,
		),
	]);

export function parseBridgeProductRegisteredControlRequest(
	value: unknown,
): BridgeProductControlRequest {
	const request = bridgeProductControlRequestSchema.parse(value);
	switch (request.kind) {
		case 'subscription.open':
			bridgeProductMetadataApplicationRegistry.validateOpen(
				request.subscription.subscriptionKind,
				request.subscription,
			);
			break;
		case 'subscription.updateBatch': {
			bridgeProductMetadataApplicationRegistry.validateInterestDelta(
				request.subscriptionKind,
				request.delta,
			);
			const deltaItemCount = bridgeProductMetadataApplicationRegistry.interestDeltaItemCount(
				request.delta,
			);
			if (deltaItemCount === 0 || deltaItemCount > request.totalDeltaItemCount) {
				throw new Error('Subscription update batch item count must fit its declared total.');
			}
			break;
		}
		case 'subscription.cancel':
			bridgeProductMetadataApplicationRegistry.lookup(request.subscriptionKind);
			break;
		case 'workerSession.resync': {
			const epochBySurface = new Map<'file' | 'review', number>();
			for (const activeSubscription of request.activeSubscriptions) {
				const protocol = bridgeProductMetadataApplicationRegistry.lookup(
					activeSubscription.subscriptionKind,
				);
				const existingEpoch = epochBySurface.get(protocol.surface);
				if (
					existingEpoch !== undefined &&
					existingEpoch !== activeSubscription.workerDerivationEpoch
				) {
					throw new Error('Active subscriptions for one surface must share one derivation epoch.');
				}
				epochBySurface.set(protocol.surface, activeSubscription.workerDerivationEpoch);
			}
			break;
		}
		case 'product.call':
		case 'workerSession.open':
			break;
	}
	return request;
}

const bridgeProductDemandLaneTag = {
	foreground: 1,
	active: 2,
	visible: 3,
	nearby: 4,
	speculative: 5,
	idle: 6,
} satisfies Readonly<Record<BridgeDemandLane, number>>;

const bridgeProductTextEncoder = new TextEncoder();

interface EncodedInterest {
	readonly keyBytes: Uint8Array;
	readonly lane: BridgeDemandLane;
}

function encodeCanonicalInterestState(
	applicationTag: number,
	interests: readonly EncodedInterest[],
	pathScope: readonly string[],
): Uint8Array {
	const encodedInterests = interests.toSorted((left, right) =>
		compareEncodedBytes(left.keyBytes, right.keyBytes),
	);
	const encodedPathScope = pathScope
		.map((path) => bridgeProductTextEncoder.encode(path))
		.toSorted(compareEncodedBytes);
	const includesPathScope = applicationTag === 2;
	const byteLength =
		2 +
		4 +
		encodedInterests.reduce(
			(totalBytes, interest) => totalBytes + 4 + interest.keyBytes.byteLength + 1,
			0,
		) +
		(includesPathScope
			? 4 +
				encodedPathScope.reduce((totalBytes, pathBytes) => totalBytes + 4 + pathBytes.byteLength, 0)
			: 0);
	const encodedState = new Uint8Array(byteLength);
	const dataView = new DataView(encodedState.buffer);
	let offsetBytes = 0;
	encodedState[offsetBytes] = 1;
	offsetBytes += 1;
	encodedState[offsetBytes] = applicationTag;
	offsetBytes += 1;
	offsetBytes = writeUint32(dataView, offsetBytes, encodedInterests.length);
	for (const interest of encodedInterests) {
		offsetBytes = writeLengthPrefixedBytes(encodedState, dataView, offsetBytes, interest.keyBytes);
		encodedState[offsetBytes] = bridgeProductDemandLaneTag[interest.lane];
		offsetBytes += 1;
	}
	if (includesPathScope) {
		offsetBytes = writeUint32(dataView, offsetBytes, encodedPathScope.length);
		for (const pathBytes of encodedPathScope) {
			offsetBytes = writeLengthPrefixedBytes(encodedState, dataView, offsetBytes, pathBytes);
		}
	}
	if (offsetBytes !== encodedState.byteLength) {
		throw new Error('Bridge product interest-state encoding length mismatch.');
	}
	return encodedState;
}

function fileEncodedInterests(state: FileMetadataInterestState): readonly EncodedInterest[] {
	return state.interests.flatMap((interest) =>
		interest.paths.map((path) => ({
			keyBytes: bridgeProductTextEncoder.encode(path),
			lane: interest.lane,
		})),
	);
}

function reviewEncodedInterests(state: ReviewMetadataInterestState): readonly EncodedInterest[] {
	return state.interests.flatMap((interest) =>
		interest.itemIds.map((itemId) => ({
			keyBytes: bridgeProductTextEncoder.encode(itemId),
			lane: interest.lane,
		})),
	);
}

function fileMetadataInterestStatePreflight(
	state: FileMetadataInterestState,
): BridgeProductMetadataApplicationInterestStateEncodingPreflight {
	return preflightCanonicalTextValues(10, [
		...state.interests.flatMap((interest) =>
			interest.paths.map((path) => ({ overheadBytes: 5, value: path })),
		),
		...state.pathScope.map((path) => ({ overheadBytes: 4, value: path })),
	]);
}

function reviewMetadataInterestStatePreflight(
	state: ReviewMetadataInterestState,
): BridgeProductMetadataApplicationInterestStateEncodingPreflight {
	return preflightCanonicalTextValues(
		6,
		state.interests.flatMap((interest) =>
			interest.itemIds.map((itemId) => ({ overheadBytes: 5, value: itemId })),
		),
	);
}

function preflightCanonicalTextValues(
	baseByteLength: number,
	textValues: readonly { readonly overheadBytes: number; readonly value: string }[],
): BridgeProductMetadataApplicationInterestStateEncodingPreflight {
	let canonicalByteLength = baseByteLength;
	let visitedTextValueCount = 0;
	for (const textValue of textValues) {
		const valueByteLength = bridgeProductUnicodeScalarUtf8ByteLength(textValue.value);
		if (valueByteLength === null) {
			throw new Error('Bridge product canonical interest-state preflight requires scalar text.');
		}
		canonicalByteLength += textValue.overheadBytes + valueByteLength;
		visitedTextValueCount += 1;
		if (canonicalByteLength > BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES) {
			return {
				canonicalByteLengthLowerBound: canonicalByteLength,
				maximumCanonicalByteLength: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
				status: 'exceedsMaximum',
				visitedTextValueCount,
			};
		}
	}
	return acceptedInterestStatePreflight(canonicalByteLength, visitedTextValueCount);
}

function acceptedInterestStatePreflight(
	canonicalByteLength: number,
	visitedTextValueCount: number,
): BridgeProductMetadataApplicationInterestStateEncodingPreflight {
	return { canonicalByteLength, status: 'accepted', visitedTextValueCount };
}

function compareEncodedBytes(left: Uint8Array, right: Uint8Array): number {
	const sharedLength = Math.min(left.byteLength, right.byteLength);
	for (let byteIndex = 0; byteIndex < sharedLength; byteIndex += 1) {
		const leftByte = left[byteIndex] ?? 0;
		const rightByte = right[byteIndex] ?? 0;
		if (leftByte !== rightByte) return leftByte - rightByte;
	}
	return left.byteLength - right.byteLength;
}

function writeLengthPrefixedBytes(
	target: Uint8Array,
	dataView: DataView,
	offsetBytes: number,
	valueBytes: Uint8Array,
): number {
	const valueOffsetBytes = writeUint32(dataView, offsetBytes, valueBytes.byteLength);
	target.set(valueBytes, valueOffsetBytes);
	return valueOffsetBytes + valueBytes.byteLength;
}

function writeUint32(dataView: DataView, offsetBytes: number, value: number): number {
	dataView.setUint32(offsetBytes, value, false);
	return offsetBytes + 4;
}

function fileMetadataInterestDelta(
	current: FileMetadataInterestState,
	target: FileMetadataInterestState,
): z.infer<typeof bridgeProductFileMetadataInterestDeltaSchema> {
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

function reviewMetadataInterestDelta(
	current: ReviewMetadataInterestState,
	target: ReviewMetadataInterestState,
): z.infer<typeof bridgeProductReviewMetadataInterestDeltaSchema> {
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

function fileInterestLanes(
	state: FileMetadataInterestState,
): ReadonlyMap<string, FileMetadataInterestState['interests'][number]['lane']> {
	return new Map(
		state.interests.flatMap((interest) => interest.paths.map((path) => [path, interest.lane])),
	);
}

function reviewInterestLanes(
	state: ReviewMetadataInterestState,
): ReadonlyMap<string, ReviewMetadataInterestState['interests'][number]['lane']> {
	return new Map(
		state.interests.flatMap((interest) =>
			interest.itemIds.map((itemId) => [itemId, interest.lane]),
		),
	);
}
