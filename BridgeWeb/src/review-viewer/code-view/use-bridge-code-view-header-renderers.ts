import { useMemo, useRef } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewFilePresentation } from './bridge-code-view-file-presentation-toggle.js';
import type { BridgeCodeViewItemPresentation } from './bridge-code-view-materialization.js';
import { createBridgeCodeViewHeaderRenderers } from './bridge-code-view-panel-support.js';

export function useBridgeCodeViewHeaderRenderers(props: {
	readonly collapsedItemIds: ReadonlySet<string>;
	readonly onFilePresentationChange?:
		| ((itemId: string, presentation: BridgeCodeViewFilePresentation) => void)
		| undefined;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
	readonly onToggleItemCollapse: (itemId: string) => void;
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly selectedItemPresentation: BridgeCodeViewItemPresentation | null;
}): ReturnType<typeof createBridgeCodeViewHeaderRenderers> {
	const {
		collapsedItemIds,
		onFilePresentationChange,
		onHeaderVisibilityChange,
		onToggleItemCollapse,
		reviewPackage,
		selectedItemId,
		selectedItemPresentation,
	} = props;
	const onFilePresentationChangeRef = useRef(onFilePresentationChange);
	onFilePresentationChangeRef.current = onFilePresentationChange;
	const selectedItemIdRef = useRef(selectedItemId);
	selectedItemIdRef.current = selectedItemId;
	const selectedItemPresentationRef = useRef(selectedItemPresentation);
	selectedItemPresentationRef.current = selectedItemPresentation;
	return useMemo(
		() =>
			createBridgeCodeViewHeaderRenderers({
				collapsedItemIds,
				isFilePresentationOpen: (itemId): boolean =>
					selectedItemIdRef.current === itemId &&
					selectedItemPresentationRef.current?.kind === 'file',
				onFilePresentationChange: (itemId, presentation): void =>
					onFilePresentationChangeRef.current?.(itemId, presentation),
				onHeaderVisibilityChange,
				onToggleItemCollapse,
				reviewPackage,
			}),
		[collapsedItemIds, onHeaderVisibilityChange, onToggleItemCollapse, reviewPackage],
	);
}
