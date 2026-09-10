import { useMemo } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { createBridgeCodeViewHeaderRenderers } from './bridge-code-view-header-renderers.js';

export function useBridgeCodeViewHeaderRenderers(props: {
	readonly collapsedItemIds: ReadonlySet<string>;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
	readonly onOpenFile: ((path: string) => void) | undefined;
	readonly onToggleItemCollapse: (itemId: string) => void;
	readonly reviewPackage: BridgeReviewPackage;
}): ReturnType<typeof createBridgeCodeViewHeaderRenderers> {
	const {
		collapsedItemIds,
		onHeaderVisibilityChange,
		onOpenFile,
		onToggleItemCollapse,
		reviewPackage,
	} = props;
	return useMemo(
		() =>
			createBridgeCodeViewHeaderRenderers({
				collapsedItemIds,
				onHeaderVisibilityChange,
				onOpenFile,
				onToggleItemCollapse,
				reviewPackage,
			}),
		[collapsedItemIds, onHeaderVisibilityChange, onOpenFile, onToggleItemCollapse, reviewPackage],
	);
}
