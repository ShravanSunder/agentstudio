import { useEffect } from 'react';

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';

export interface UseBridgeReviewContentIdentityControllerProps {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly reviewPackage: BridgeReviewPackage | null;
}

export function useBridgeReviewContentIdentityController(
	props: UseBridgeReviewContentIdentityControllerProps,
): void {
	const { contentRegistry, reviewPackage } = props;
	useEffect((): void => {
		contentRegistry.setActiveIdentity(
			reviewPackage === null
				? null
				: {
						packageId: reviewPackage.packageId,
						reviewGeneration: reviewPackage.reviewGeneration,
						revision: reviewPackage.revision,
					},
		);
	}, [contentRegistry, reviewPackage]);
}
