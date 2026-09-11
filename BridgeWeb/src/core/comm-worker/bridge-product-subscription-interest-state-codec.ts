import { bridgeProductMetadataApplicationRegistry } from './bridge-product-metadata-application-registry.js';
import type { BridgeProductSubscriptionInterestState } from './bridge-product-subscription-contracts.js';

export const BRIDGE_PRODUCT_INTEREST_STATE_FORMAT_VERSION = 1 as const;

export function encodeBridgeProductSubscriptionInterestState(
	state: BridgeProductSubscriptionInterestState,
): Uint8Array {
	return bridgeProductMetadataApplicationRegistry.encodeInterestState(state);
}
