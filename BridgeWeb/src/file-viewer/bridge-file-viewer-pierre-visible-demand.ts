import type { useFileTree } from '@pierre/trees/react';

import {
	pierreTreeScrollOwnerForModel,
	visiblePierreFileRowElementsForModel,
	type BridgePierreFileRowElement,
	type BridgePierreTreeScrollOwner,
} from '../app/bridge-pierre-tree-adapter.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeVisibleIdsCaptureTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-contracts.js';
import type { BridgeFileViewerDisplayTreeRow } from './bridge-file-viewer-display-model.js';

type PierreFileTreeModel = ReturnType<typeof useFileTree>['model'];
export type PierreVisibleFileRowElement = BridgePierreFileRowElement;

export function pierreFileTreeScrollElementForDemand(
	model: PierreFileTreeModel,
): BridgePierreTreeScrollOwner | null {
	return pierreTreeScrollOwnerForModel(model);
}

export function visibleFileDemandChangeForPierreDemand(props: {
	readonly model: PierreFileTreeModel;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly treeRowByPath: {
		readonly get: (path: string) => BridgeFileViewerDisplayTreeRow | undefined;
	};
}): BridgeFileViewerVisibleFileDemandChange | null {
	const startedAt = performance.now();
	const rowElements = visiblePierreFileRowElementsForModel(props.model);
	const demandChange = visibleFileDemandChangeForPierreVisibleFileRows({
		rowElements,
		treeRowByPath: props.treeRowByPath,
	});
	if (props.telemetryRecorder !== undefined) {
		recordBridgeTreeVisibleIdsCaptureTelemetrySample({
			durationMilliseconds: performance.now() - startedAt,
			returnedDescriptorCount: 0,
			returnedItemCount: demandChange?.visibleItemIds.length ?? 0,
			rowCount: rowElements.length,
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.telemetryTraceContext ?? null,
			viewer: 'file',
		});
	}
	return demandChange;
}

export function visibleFileDemandChangeForPierreVisibleFileRows(props: {
	readonly rowElements: Iterable<PierreVisibleFileRowElement>;
	readonly treeRowByPath: {
		readonly get: (path: string) => BridgeFileViewerDisplayTreeRow | undefined;
	};
}): BridgeFileViewerVisibleFileDemandChange | null {
	const visibleItemIds: string[] = [];
	const visibleItemIndexes: number[] = [];
	const seenItemIds = new Set<string>();
	for (const rowElement of props.rowElements) {
		const path = rowElement.getAttribute('data-item-path');
		if (path === null) {
			continue;
		}
		const row = props.treeRowByPath.get(path);
		if (row?.fileId === null || row?.fileId === undefined || seenItemIds.has(row.fileId)) {
			continue;
		}
		seenItemIds.add(row.fileId);
		visibleItemIds.push(row.fileId);
		visibleItemIndexes.push(row.projectionIndex);
	}
	return visibleItemIds.length === 0
		? null
		: {
				firstVisibleIndex: Math.min(...visibleItemIndexes),
				lastVisibleIndex: Math.max(...visibleItemIndexes),
				visibleFileCount: visibleItemIds.length,
				visibleItemIds,
				visibleItemIndexes,
			};
}
