import type { BridgeProductSubscriptionInterestDeltaWire } from './bridge-product-subscription-contracts.js';

export function bridgeProductSubscriptionInterestDeltaItemCount(
	delta: BridgeProductSubscriptionInterestDeltaWire,
): number {
	switch (delta.subscriptionKind) {
		case 'file.metadata':
			return (
				delta.add.length +
				delta.removePaths.length +
				delta.addPathScope.length +
				delta.removePathScope.length
			);
		case 'review.metadata':
			return delta.add.length + delta.removeItemIds.length;
	}
	throw new Error('Unsupported Bridge product subscription interest delta.');
}
