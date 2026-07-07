import type { useFileTree } from '@pierre/trees/react';

import {
	pierreTreeScrollOwnerForModel,
	visiblePierreFileRowElementsForModel,
	type BridgePierreFileRowElement,
	type BridgePierreTreeScrollOwner,
} from '../app/bridge-pierre-tree-adapter.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeVisibleIdsCaptureTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-contracts.js';

type PierreFileTreeModel = ReturnType<typeof useFileTree>['model'];

export type PierreVisibleFileRowElement = BridgePierreFileRowElement;

export function pierreFileTreeScrollElementForDemand(
	model: PierreFileTreeModel,
): BridgePierreTreeScrollOwner | null {
	return pierreTreeScrollOwnerForModel(model);
}

export function visibleDescriptorRefsForPierreDemand(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly model: PierreFileTreeModel;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): readonly BridgeDescriptorRef[] {
	return (
		visibleFileDemandChangeForPierreDemand({
			fileDescriptorByPath: props.fileDescriptorByPath,
			model: props.model,
			telemetryRecorder: props.telemetryRecorder,
			telemetryTraceContext: props.telemetryTraceContext,
			treeRows: props.treeRows,
		})?.descriptorRefs ?? []
	);
}

export function visibleFileDemandChangeForPierreDemand(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly model: PierreFileTreeModel;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): BridgeFileViewerVisibleFileDemandChange | null {
	const startedAt = performance.now();
	const rowElements = visiblePierreFileRowElementsForModel(props.model);
	const demandChange = visibleFileDemandChangeForPierreVisibleFileRows({
		fileDescriptorByPath: props.fileDescriptorByPath,
		rowElements,
		treeRowIndexByPath: treeRowIndexByPathFromFileViewerTreeRows(props.treeRows),
	});
	if (props.telemetryRecorder !== undefined) {
		recordBridgeTreeVisibleIdsCaptureTelemetrySample({
			durationMilliseconds: performance.now() - startedAt,
			returnedDescriptorCount: demandChange?.descriptorRefs.length ?? 0,
			returnedItemCount: 0,
			rowCount: rowElements.length,
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.telemetryTraceContext ?? null,
			viewer: 'file',
		});
	}
	return demandChange;
}

export function descriptorRefsForPierreVisibleFileRows(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly rowElements: Iterable<PierreVisibleFileRowElement>;
	readonly treeRowIndexByPath: ReadonlyMap<string, number>;
}): readonly BridgeDescriptorRef[] {
	return visibleFileDemandChangeForPierreVisibleFileRows(props)?.descriptorRefs ?? [];
}

export function visibleFileDemandChangeForPierreVisibleFileRows(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly rowElements: Iterable<PierreVisibleFileRowElement>;
	readonly treeRowIndexByPath: ReadonlyMap<string, number>;
}): BridgeFileViewerVisibleFileDemandChange | null {
	const descriptorRefs: BridgeDescriptorRef[] = [];
	const visibleItemIds: string[] = [];
	const visibleItemIndexes: number[] = [];
	const seenDescriptorIds = new Set<string>();
	for (const rowElement of props.rowElements) {
		const path = rowElement.getAttribute('data-item-path');
		if (path === null) {
			continue;
		}
		const descriptor = props.fileDescriptorByPath.get(path);
		if (
			descriptor === undefined ||
			!canFetchWorktreeFileDescriptorContent(descriptor) ||
			seenDescriptorIds.has(descriptor.contentDescriptor.ref.descriptorId)
		) {
			continue;
		}
		const visibleItemIndex = props.treeRowIndexByPath.get(path);
		if (visibleItemIndex === undefined) {
			continue;
		}
		seenDescriptorIds.add(descriptor.contentDescriptor.ref.descriptorId);
		descriptorRefs.push(descriptor.contentDescriptor.ref);
		visibleItemIds.push(descriptor.fileId);
		visibleItemIndexes.push(visibleItemIndex);
	}
	return descriptorRefs.length === 0
		? null
		: {
				descriptorRefs,
				firstVisibleIndex: Math.min(...visibleItemIndexes),
				lastVisibleIndex: Math.max(...visibleItemIndexes),
				visibleItemIds,
				visibleItemIndexes,
				visibleFileCount: descriptorRefs.length,
			};
}

export function treeRowIndexByPathFromFileViewerTreeRows(
	treeRows: readonly WorktreeTreeRowMetadata[],
): ReadonlyMap<string, number> {
	return new Map(treeRows.map((row, index): readonly [string, number] => [row.path, index]));
}
