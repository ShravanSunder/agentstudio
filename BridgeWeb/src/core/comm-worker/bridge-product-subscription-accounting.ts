import { bridgeProductMetadataApplicationRegistry } from './bridge-product-metadata-application-registry.js';
import type { BridgeProductSubscriptionInterestDeltaWire } from './bridge-product-subscription-contracts.js';

export function bridgeProductSubscriptionInterestDeltaItemCount(
	delta: BridgeProductSubscriptionInterestDeltaWire,
): number {
	return bridgeProductMetadataApplicationRegistry.interestDeltaItemCount(delta);
}
