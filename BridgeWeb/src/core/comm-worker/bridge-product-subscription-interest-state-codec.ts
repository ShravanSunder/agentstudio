import type { BridgeDemandLane } from '../models/bridge-demand-models.js';
import {
	type BridgeProductSubscriptionInterestState,
	validateBridgeProductSubscriptionInterestState,
} from './bridge-product-subscription-contracts.js';

export const BRIDGE_PRODUCT_INTEREST_STATE_FORMAT_VERSION = 1 as const;

const bridgeProductSubscriptionKindTag = {
	'file.metadata': 2,
	'review.metadata': 1,
} as const;

const bridgeProductDemandLaneTag = {
	foreground: 1,
	active: 2,
	visible: 3,
	nearby: 4,
	speculative: 5,
	idle: 6,
} as const satisfies Readonly<Record<BridgeDemandLane, number>>;

const bridgeProductTextEncoder = new TextEncoder();

type EncodedInterest = {
	readonly keyBytes: Uint8Array;
	readonly lane: BridgeDemandLane;
};

export function encodeBridgeProductSubscriptionInterestState(
	state: BridgeProductSubscriptionInterestState,
): Uint8Array {
	const validatedState = validateBridgeProductSubscriptionInterestState(state);
	const encodedInterests = (
		validatedState.subscriptionKind === 'file.metadata'
			? validatedState.interests.flatMap((interest): readonly EncodedInterest[] =>
					interest.paths.map((path) => ({
						keyBytes: bridgeProductTextEncoder.encode(path),
						lane: interest.lane,
					})),
				)
			: validatedState.interests.flatMap((interest): readonly EncodedInterest[] =>
					interest.itemIds.map((itemId) => ({
						keyBytes: bridgeProductTextEncoder.encode(itemId),
						lane: interest.lane,
					})),
				)
	).toSorted(compareEncodedInterestKeys);
	const encodedPathScope =
		validatedState.subscriptionKind === 'file.metadata'
			? validatedState.pathScope
					.map((path) => bridgeProductTextEncoder.encode(path))
					.toSorted(compareEncodedBytes)
			: [];
	const byteLength =
		2 +
		4 +
		encodedInterests.reduce(
			(totalBytes, interest) => totalBytes + 4 + interest.keyBytes.byteLength + 1,
			0,
		) +
		(validatedState.subscriptionKind === 'file.metadata'
			? 4 +
				encodedPathScope.reduce((totalBytes, pathBytes) => totalBytes + 4 + pathBytes.byteLength, 0)
			: 0);
	const encodedState = new Uint8Array(byteLength);
	const dataView = new DataView(encodedState.buffer);
	let offsetBytes = 0;

	encodedState[offsetBytes] = BRIDGE_PRODUCT_INTEREST_STATE_FORMAT_VERSION;
	offsetBytes += 1;
	encodedState[offsetBytes] = bridgeProductSubscriptionKindTag[validatedState.subscriptionKind];
	offsetBytes += 1;
	offsetBytes = writeUint32(dataView, offsetBytes, encodedInterests.length);
	for (const interest of encodedInterests) {
		offsetBytes = writeLengthPrefixedBytes(encodedState, dataView, offsetBytes, interest.keyBytes);
		encodedState[offsetBytes] = bridgeProductDemandLaneTag[interest.lane];
		offsetBytes += 1;
	}
	if (validatedState.subscriptionKind === 'file.metadata') {
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

function compareEncodedInterestKeys(left: EncodedInterest, right: EncodedInterest): number {
	return compareEncodedBytes(left.keyBytes, right.keyBytes);
}

function compareEncodedBytes(left: Uint8Array, right: Uint8Array): number {
	const sharedLength = Math.min(left.byteLength, right.byteLength);
	for (let byteIndex = 0; byteIndex < sharedLength; byteIndex += 1) {
		const leftByte = left[byteIndex] ?? 0;
		const rightByte = right[byteIndex] ?? 0;
		if (leftByte !== rightByte) {
			return leftByte - rightByte;
		}
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
