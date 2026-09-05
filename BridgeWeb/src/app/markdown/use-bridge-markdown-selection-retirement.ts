import { useEffect, useRef } from 'react';

import type { BridgeMainRenderFulfillmentCoordinator } from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';

export function useBridgeMarkdownSelectionRetirement(props: {
	readonly coordinator: Pick<BridgeMainRenderFulfillmentCoordinator, 'supersedeItem'>;
	readonly displayedItemId: string | null;
}): void {
	const displayedItemIdRef = useRef<string | null>(null);
	useEffect((): void => {
		const previousItemId = displayedItemIdRef.current;
		if (previousItemId !== null && previousItemId !== props.displayedItemId) {
			props.coordinator.supersedeItem(previousItemId, 'stale_submission');
		}
		displayedItemIdRef.current = props.displayedItemId;
	}, [props.coordinator, props.displayedItemId]);
}
