import type { BridgeProductMetadataApplicationInterestStateEncodingPreflight } from './bridge-product-metadata-application-protocol.js';
import { bridgeProductMetadataApplicationRegistry } from './bridge-product-metadata-application-registry.js';
import type { BridgeProductSubscriptionInterestState } from './bridge-product-subscription-contracts.js';

export type BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight =
	BridgeProductMetadataApplicationInterestStateEncodingPreflight;

export function preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(
	state: BridgeProductSubscriptionInterestState,
): BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight {
	return bridgeProductMetadataApplicationRegistry.preflightInterestState(state);
}
