import type { useFileTree } from '@pierre/trees/react';

import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';

type PierreFileTreeModel = ReturnType<typeof useFileTree>['model'];

export interface PierreVisibleFileRowElement {
	readonly getAttribute: (name: string) => string | null;
}

export function pierreFileTreeScrollElementForDemand(
	model: PierreFileTreeModel,
): HTMLElement | null {
	const fileTreeContainer = model.getFileTreeContainer();
	const rowContainer = fileTreeContainer?.shadowRoot ?? fileTreeContainer;
	return (
		rowContainer?.querySelector<HTMLElement>('[data-file-tree-virtualized-scroll="true"]') ?? null
	);
}

export function visibleDescriptorRefsForPierreDemand(props: {
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly model: PierreFileTreeModel;
}): readonly BridgeDescriptorRef[] {
	const fileTreeContainer = props.model.getFileTreeContainer();
	const rowContainer = fileTreeContainer?.shadowRoot ?? fileTreeContainer;
	if (rowContainer === undefined || rowContainer === null) {
		return [];
	}
	return descriptorRefsForPierreVisibleFileRows({
		fileDescriptorByPath: props.fileDescriptorByPath,
		rowElements: rowContainer.querySelectorAll<HTMLElement>(
			'[data-type="item"][data-item-type="file"][data-item-path]',
		),
	});
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
