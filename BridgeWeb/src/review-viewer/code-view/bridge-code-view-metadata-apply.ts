import type { CodeViewItem } from '@pierre/diffs';

import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';

export interface BridgeCodeViewMetadataReconcileProps {
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly metadataItems: readonly BridgeCodeViewItem[];
	readonly preserveItemIds?: readonly string[];
}

export interface ApplyBridgeCodeViewMetadataItemsProps {
	readonly applyItemUpdate: (item: BridgeCodeViewItem) => void;
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly items: readonly BridgeCodeViewItem[];
	readonly setItems: (items: readonly BridgeCodeViewItem[]) => void;
	readonly sourceReset: boolean;
}

export function applyBridgeCodeViewMetadataItems(
	props: ApplyBridgeCodeViewMetadataItemsProps,
): void {
	if (props.sourceReset) {
		props.setItems(props.items);
		return;
	}
	for (const item of props.items) {
		props.applyItemUpdate(item);
	}
}
