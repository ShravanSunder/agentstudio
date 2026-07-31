import type { BridgeProductFileTreeFileClass } from '../core/comm-worker/bridge-product-subscription-contracts.js';

export type BridgeFileViewerFilterMode = 'all' | BridgeProductFileTreeFileClass;
export type BridgeFileViewerSearchMode = 'text' | 'regex';

export interface BridgeFileViewerVisibleFileDemandChange {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
	readonly visibleItemIndexes: readonly number[];
	readonly visibleFileCount: number;
}
