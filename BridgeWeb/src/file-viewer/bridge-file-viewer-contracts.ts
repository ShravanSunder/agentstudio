import type {
	BridgeFileViewerDisplayItem,
	BridgeFileViewerDisplayTreeRow,
} from './bridge-file-viewer-display-model.js';

export type BridgeFileViewerFilterMode = 'all' | 'fetchable' | 'unavailable';
export type BridgeFileViewerSearchMode = 'text' | 'regex';

export interface BridgeFileViewerDescriptorProjection {
	/** Legacy-only compatibility for unmounted harnesses; mounted File View uses displayItems. */
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly displayItems: readonly BridgeFileViewerDisplayItem[];
	readonly paths: readonly string[];
	readonly searchError: string | null;
	readonly treeRows: readonly BridgeFileViewerDisplayTreeRow[];
}

export interface BridgeFileViewerVisibleFileDemandChange {
	/** Legacy-only compatibility; mounted File View sends item ids and indexes only. */
	readonly descriptorRefs: readonly BridgeDescriptorRef[];
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
	readonly visibleItemIndexes: readonly number[];
	readonly visibleFileCount: number;
}
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
