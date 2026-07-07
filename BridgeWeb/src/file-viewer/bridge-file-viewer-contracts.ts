import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';

export type BridgeFileViewerFilterMode = 'all' | 'fetchable' | 'unavailable';
export type BridgeFileViewerSearchMode = 'text' | 'regex';

export interface BridgeFileViewerDescriptorProjection {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly paths: readonly string[];
	readonly searchError: string | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}

export interface BridgeFileViewerVisibleFileDemandChange {
	readonly descriptorRefs: readonly BridgeDescriptorRef[];
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
	readonly visibleItemIndexes: readonly number[];
	readonly visibleFileCount: number;
}
