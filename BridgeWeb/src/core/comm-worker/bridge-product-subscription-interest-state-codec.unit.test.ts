import { Buffer } from 'node:buffer';

import { describe, expect, test } from 'vitest';

import {
	bridgeProductDisplayPathSchema,
	bridgeProductSafeMessageSchema,
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
} from './bridge-product-contract-primitives.js';
import {
	type BridgeProductSubscriptionInterestState,
	bridgeProductFileMetadataInterestDeltaSchema,
	bridgeProductReviewMetadataInterestDeltaSchema,
	preflightBridgeProductSubscriptionInterestStateCanonicalEncoding,
	validateBridgeProductSubscriptionInterestState,
} from './bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from './bridge-product-subscription-interest-state-codec.js';

describe('Bridge product subscription interest-state codec', () => {
	test('rejects unpaired UTF-16 surrogates before lossy UTF-8 encoding', () => {
		const firstLoneSurrogate = '\ud800';
		const secondLoneSurrogate = '\udbff';
		const loneTrailingSurrogate = '\udfff';
		const validScalarPair = '\ud83d\ude80';
		const textEncoder = new TextEncoder();

		expect(firstLoneSurrogate).not.toBe(secondLoneSurrogate);
		expect(Buffer.from(textEncoder.encode(firstLoneSurrogate))).toEqual(
			Buffer.from(textEncoder.encode(secondLoneSurrogate)),
		);
		expect(bridgeProductDisplayPathSchema.safeParse(firstLoneSurrogate).success).toBe(false);
		expect(bridgeProductDisplayPathSchema.safeParse(secondLoneSurrogate).success).toBe(false);
		expect(bridgeProductDisplayPathSchema.safeParse(loneTrailingSurrogate).success).toBe(false);
		expect(bridgeProductSafeMessageSchema.safeParse(firstLoneSurrogate).success).toBe(false);
		expect(bridgeProductSafeMessageSchema.safeParse(secondLoneSurrogate).success).toBe(false);
		expect(bridgeProductSafeMessageSchema.safeParse(loneTrailingSurrogate).success).toBe(false);
		expect(bridgeProductDisplayPathSchema.safeParse(`src/${validScalarPair}.ts`).success).toBe(
			true,
		);
		expect(bridgeProductSafeMessageSchema.safeParse(`Opened ${validScalarPair}`).success).toBe(
			true,
		);
	});

	test('accepts exactly 256 KiB of canonical interest state and rejects the next byte', () => {
		const maximumState = makeBoundaryFileInterestState(49);
		const oversizedState = makeBoundaryFileInterestState(50);

		expect(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES).toBe(256 * 1024);
		expect(preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(maximumState)).toEqual({
			canonicalByteLength: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
			status: 'accepted',
			visitedTextValueCount: 65,
		});
		expect(encodeBridgeProductSubscriptionInterestState(maximumState).byteLength).toBe(
			BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
		);
		expect(
			preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(oversizedState),
		).toEqual({
			canonicalByteLengthLowerBound: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES + 1,
			maximumCanonicalByteLength: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
			status: 'exceedsMaximum',
			visitedTextValueCount: 65,
		});
		expect(() => encodeBridgeProductSubscriptionInterestState(oversizedState)).toThrow(
			/256 KiB|262144|canonical interest state/iu,
		);
	});

	test('stops preflight before retaining the theoretical 82,010,010-byte File state', () => {
		const maximumLengthPath = 'x'.repeat(4096);
		const maximumCountPaths = Array.from({ length: 10_000 }, () => maximumLengthPath);
		const worstCaseState = {
			interests: [{ lane: 'foreground' as const, paths: maximumCountPaths }],
			pathScope: maximumCountPaths,
			subscriptionKind: 'file.metadata' as const,
		};
		const theoreticalCanonicalByteLength =
			10 + 10_000 * (5 + maximumLengthPath.length) + 10_000 * (4 + maximumLengthPath.length);

		expect(theoreticalCanonicalByteLength).toBe(82_010_010);
		expect(
			preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(worstCaseState),
		).toEqual({
			canonicalByteLengthLowerBound: 262_474,
			maximumCanonicalByteLength: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
			status: 'exceedsMaximum',
			visitedTextValueCount: 64,
		});
		expect(() => validateBridgeProductSubscriptionInterestState(worstCaseState)).toThrow(
			/canonical interest state/iu,
		);
		expect(() => encodeBridgeProductSubscriptionInterestState(worstCaseState)).toThrow(
			/canonical interest state/iu,
		);
	});

	test('treats canonically equivalent path members as distinct UTF-8 identities', () => {
		const composedPath = 'src/\u00e9.swift';
		const decomposedPath = 'src/e\u0301.swift';
		const state = {
			interests: [{ lane: 'foreground' as const, paths: [composedPath, decomposedPath] }],
			pathScope: ['scope/\u00e9', 'scope/e\u0301'],
			subscriptionKind: 'file.metadata' as const,
		};

		expect(composedPath).not.toBe(decomposedPath);
		expect(Buffer.from(new TextEncoder().encode(composedPath))).not.toEqual(
			Buffer.from(new TextEncoder().encode(decomposedPath)),
		);
		expect(validateBridgeProductSubscriptionInterestState(state)).toEqual(state);
		expect(() => encodeBridgeProductSubscriptionInterestState(state)).not.toThrow();
		expect(
			bridgeProductFileMetadataInterestDeltaSchema.safeParse({
				add: [{ lane: 'foreground', path: composedPath }],
				addPathScope: ['scope/\u00e9'],
				removePathScope: ['scope/e\u0301'],
				removePaths: [decomposedPath],
				subscriptionKind: 'file.metadata',
			}).success,
		).toBe(true);
	});

	test('treats canonically equivalent Review item IDs as distinct UTF-8 identities', () => {
		const composedItemId = 'review-\u00e9';
		const decomposedItemId = 'review-e\u0301';
		const state = {
			interests: [
				{
					itemIds: [composedItemId, decomposedItemId],
					lane: 'foreground' as const,
				},
			],
			subscriptionKind: 'review.metadata' as const,
		};

		expect(composedItemId).not.toBe(decomposedItemId);
		expect(Buffer.from(new TextEncoder().encode(composedItemId))).not.toEqual(
			Buffer.from(new TextEncoder().encode(decomposedItemId)),
		);
		expect(validateBridgeProductSubscriptionInterestState(state)).toEqual(state);
		expect(() => encodeBridgeProductSubscriptionInterestState(state)).not.toThrow();
		expect(
			bridgeProductReviewMetadataInterestDeltaSchema.safeParse({
				add: [{ itemId: composedItemId, lane: 'foreground' }],
				removeItemIds: [decomposedItemId],
				subscriptionKind: 'review.metadata',
			}).success,
		).toBe(true);
	});

	test('bounds Review item IDs by exact scalar UTF-8 bytes', () => {
		const exactMaximumItemId = '\u00e9'.repeat(64);
		const oversizedItemId = `a${exactMaximumItemId}`;
		const invalidScalarItemId = '\ud800';

		expect(new TextEncoder().encode(exactMaximumItemId).byteLength).toBe(128);
		expect(new TextEncoder().encode(oversizedItemId).byteLength).toBe(129);
		expect(
			validateBridgeProductSubscriptionInterestState({
				interests: [{ itemIds: [exactMaximumItemId], lane: 'foreground' }],
				subscriptionKind: 'review.metadata',
			}),
		).toEqual({
			interests: [{ itemIds: [exactMaximumItemId], lane: 'foreground' }],
			subscriptionKind: 'review.metadata',
		});
		for (const rejectedItemId of ['', oversizedItemId, invalidScalarItemId]) {
			expect(() =>
				validateBridgeProductSubscriptionInterestState({
					interests: [{ itemIds: [rejectedItemId], lane: 'foreground' }],
					subscriptionKind: 'review.metadata',
				}),
			).toThrow();
			expect(
				bridgeProductReviewMetadataInterestDeltaSchema.safeParse({
					add: [{ itemId: rejectedItemId, lane: 'foreground' }],
					removeItemIds: [],
					subscriptionKind: 'review.metadata',
				}).success,
			).toBe(false);
		}
	});
});

function makeBoundaryFileInterestState(
	finalPathByteLength: number,
): BridgeProductSubscriptionInterestState {
	return {
		interests: [
			{
				lane: 'foreground' as const,
				paths: [
					...Array.from({ length: 64 }, (_, pathIndex) =>
						makeFixedLengthAsciiPath(pathIndex, 4090),
					),
					makeFixedLengthAsciiPath(64, finalPathByteLength),
				],
			},
		],
		pathScope: [],
		subscriptionKind: 'file.metadata' as const,
	};
}

function makeFixedLengthAsciiPath(pathIndex: number, byteLength: number): string {
	const prefix = `${pathIndex.toString().padStart(5, '0')}:`;
	return `${prefix}${'x'.repeat(byteLength - prefix.length)}`;
}
