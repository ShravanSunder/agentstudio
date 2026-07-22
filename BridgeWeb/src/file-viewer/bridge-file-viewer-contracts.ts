export type BridgeFileViewerFilterMode = 'all' | 'fetchable' | 'unavailable';
export type BridgeFileViewerSearchMode = 'text' | 'regex';

export interface BridgeFileViewerVisibleFileDemandChange {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
	readonly visibleItemIndexes: readonly number[];
	readonly visibleFileCount: number;
}
