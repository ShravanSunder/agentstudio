import type { useFileTree } from '@pierre/trees/react';

import {
	pierreTreeScrollOwnerForModel,
	visiblePierreFileRowElementsForModel,
	type BridgePierreFileRowElement,
	type BridgePierreTreeScrollOwner,
} from '../app/bridge-pierre-tree-adapter.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeVisibleIdsCaptureTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';

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
}): readonly BridgeDescriptorRef[] {
	const startedAt = performance.now();
	const rowElements = visiblePierreFileRowElementsForModel(props.model);
	const descriptorRefs = descriptorRefsForPierreVisibleFileRows({
		fileDescriptorByPath: props.fileDescriptorByPath,
		rowElements,
	});
	if (props.telemetryRecorder !== undefined) {
		recordBridgeTreeVisibleIdsCaptureTelemetrySample({
			durationMilliseconds: performance.now() - startedAt,
			returnedDescriptorCount: descriptorRefs.length,
			returnedItemCount: 0,
			rowCount: rowElements.length,
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.telemetryTraceContext ?? null,
			viewer: 'file',
		});
	}
	return descriptorRefs;
}

export function descriptorRefsForPierreVisibleFileRows(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly rowElements: Iterable<PierreVisibleFileRowElement>;
}): readonly BridgeDescriptorRef[] {
	const descriptorRefs: BridgeDescriptorRef[] = [];
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
		seenDescriptorIds.add(descriptor.contentDescriptor.ref.descriptorId);
		descriptorRefs.push(descriptor.contentDescriptor.ref);
	}
	return descriptorRefs;
}
