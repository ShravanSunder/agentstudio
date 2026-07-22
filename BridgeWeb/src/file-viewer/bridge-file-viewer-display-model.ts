import type {
	BridgeMainFileItemDisplayPayload,
	BridgeMainFileStatusDisplayPayload,
	BridgeMainFileTreeDisplayRow,
	BridgeMainRenderSnapshot,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerContentAvailabilityPatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';

export interface BridgeFileViewerDisplayItem extends BridgeMainFileItemDisplayPayload {
	readonly fileId: string;
	readonly path: string;
}

export type BridgeFileViewerDisplayTreeRow = BridgeMainFileTreeDisplayRow;

export interface BridgeFileViewerDisplaySource {
	readonly generation: number;
	readonly sourceId: string;
}

export interface BridgeFileViewerDisplayModel {
	readonly fileItemById: BridgeFileViewerDisplayItemIndex;
	readonly projectedRowCount: number;
	readonly searchError: string | null;
	readonly source: BridgeFileViewerDisplaySource | null;
	readonly status: BridgeMainFileStatusDisplayPayload | null;
	readonly treeRowByPath: {
		readonly get: (path: string) => BridgeFileViewerDisplayTreeRow | undefined;
	};
	readonly totalRowCount: number;
	readonly firstFileRow: BridgeFileViewerDisplayTreeRow | null;
}

export interface BridgeFileViewerDisplayItemIndex {
	readonly size: number;
	readonly get: (fileId: string) => BridgeFileViewerDisplayItem | undefined;
}

export interface BridgeFileViewerSelection {
	readonly fileId: string;
	readonly path: string;
}

export type BridgeFileViewerOpenState =
	| { readonly status: 'idle' }
	| {
			readonly displayItem: BridgeFileViewerDisplayItem | null;
			readonly fileId: string;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'stale' | 'unavailable';
	  };

type BridgeFileDisplaySnapshot = Pick<
	BridgeMainRenderSnapshot,
	'fileDisplayFreshness' | 'fileItemById' | 'fileQuerySlice' | 'fileStatusSlice' | 'fileTreeSlice'
>;

export function bridgeFileViewerDisplayModelForSnapshot(
	snapshot: BridgeFileDisplaySnapshot,
): BridgeFileViewerDisplayModel {
	return {
		fileItemById: bridgeFileViewerDisplayItemIndex(snapshot.fileItemById),
		projectedRowCount:
			snapshot.fileQuerySlice?.projectedRowCount ?? snapshot.fileTreeSlice.index.size,
		searchError: snapshot.fileQuerySlice?.searchError ?? null,
		source:
			snapshot.fileTreeSlice.sourceId === null || snapshot.fileTreeSlice.sourceGeneration === null
				? null
				: {
						generation: snapshot.fileTreeSlice.sourceGeneration,
						sourceId: snapshot.fileTreeSlice.sourceId,
					},
		status: snapshot.fileStatusSlice,
		treeRowByPath: { get: (path) => snapshot.fileTreeSlice.index.rowForPath(path) },
		totalRowCount: snapshot.fileQuerySlice?.totalRowCount ?? snapshot.fileTreeSlice.index.size,
		firstFileRow: snapshot.fileTreeSlice.index.firstFileRow(),
	};
}

function bridgeFileViewerDisplayItemIndex(fileItemsById: {
	readonly get: (fileId: string) => BridgeMainFileItemDisplayPayload | undefined;
	readonly size: number;
}): BridgeFileViewerDisplayItemIndex {
	return {
		size: fileItemsById.size,
		get: (fileId): BridgeFileViewerDisplayItem | undefined => {
			const payload = fileItemsById.get(fileId);
			return payload === undefined ? undefined : { ...payload, fileId, path: payload.displayPath };
		},
	};
}

export function bridgeFileViewerOpenStateForSelection(props: {
	readonly contentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly displayItem: BridgeFileViewerDisplayItem | null;
	readonly hasPierreItem: boolean;
	readonly selection: BridgeFileViewerSelection | null;
	readonly status: BridgeMainFileStatusDisplayPayload | null;
}): BridgeFileViewerOpenState {
	if (props.selection === null) {
		return { status: 'idle' };
	}
	const selected = {
		displayItem: props.displayItem,
		fileId: props.selection.fileId,
		path: props.selection.path,
	} as const;
	if (props.status?.state === 'stale' || props.contentAvailability?.state === 'stale') {
		return { ...selected, status: 'stale' };
	}
	if (
		props.displayItem?.availability.kind === 'binary' ||
		props.displayItem?.availability.kind === 'unavailable' ||
		props.contentAvailability?.state === 'unavailable'
	) {
		return { ...selected, status: 'unavailable' };
	}
	if (props.contentAvailability?.state === 'failed') {
		return { ...selected, status: 'failed' };
	}
	if (props.contentAvailability?.state === 'ready' && props.hasPierreItem) {
		return { ...selected, status: 'ready' };
	}
	return { ...selected, status: 'loading' };
}

export function bridgeFileViewerPierrePathForDisplayRow(
	row: BridgeFileViewerDisplayTreeRow,
): string {
	return row.isDirectory && !row.path.endsWith('/') ? `${row.path}/` : row.path;
}
