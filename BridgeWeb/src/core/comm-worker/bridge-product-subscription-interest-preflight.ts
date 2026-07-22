import {
	bridgeProductUnicodeScalarUtf8ByteLength,
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
} from './bridge-product-contract-primitives.js';
import type { BridgeProductSubscriptionInterestState } from './bridge-product-subscription-contracts.js';

export type BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight =
	| {
			readonly canonicalByteLength: number;
			readonly status: 'accepted';
			readonly visitedTextValueCount: number;
	  }
	| {
			readonly canonicalByteLengthLowerBound: number;
			readonly maximumCanonicalByteLength: number;
			readonly status: 'exceedsMaximum';
			readonly visitedTextValueCount: number;
	  };

export function preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(
	state: BridgeProductSubscriptionInterestState,
): BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight {
	let canonicalByteLength = state.subscriptionKind === 'file.metadata' ? 10 : 6;
	let visitedTextValueCount = 0;
	const addTextValue = (
		value: string,
		perValueOverheadBytes: number,
	): BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight | null => {
		const valueByteLength = bridgeProductUnicodeScalarUtf8ByteLength(value);
		if (valueByteLength === null) {
			throw new Error('Bridge product canonical interest-state preflight requires scalar text.');
		}
		canonicalByteLength += perValueOverheadBytes + valueByteLength;
		visitedTextValueCount += 1;
		if (canonicalByteLength <= BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES) {
			return null;
		}
		return {
			canonicalByteLengthLowerBound: canonicalByteLength,
			maximumCanonicalByteLength: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
			status: 'exceedsMaximum',
			visitedTextValueCount,
		};
	};

	if (state.subscriptionKind === 'file.metadata') {
		for (const interest of state.interests) {
			for (const path of interest.paths) {
				const exceeded = addTextValue(path, 5);
				if (exceeded !== null) return exceeded;
			}
		}
		for (const path of state.pathScope) {
			const exceeded = addTextValue(path, 4);
			if (exceeded !== null) return exceeded;
		}
	} else {
		for (const interest of state.interests) {
			for (const itemId of interest.itemIds) {
				const exceeded = addTextValue(itemId, 5);
				if (exceeded !== null) return exceeded;
			}
		}
	}

	return {
		canonicalByteLength,
		status: 'accepted',
		visitedTextValueCount,
	};
}
