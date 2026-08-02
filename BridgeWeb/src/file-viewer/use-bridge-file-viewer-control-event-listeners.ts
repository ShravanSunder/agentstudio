import { useLayoutEffect } from 'react';

import {
	invalidBridgeAppControlProbeCommand,
	nextBridgeAppControlProbeSequence,
	publishBridgeAppControlProbe,
} from '../app/bridge-app-control-probe.js';
import {
	bridgeAppControlCommandRejectionReason,
	bridgeAppControlCommandSchema,
	type BridgeAppControlCommand,
} from '../app/bridge-app-control.js';
import type { BridgeViewerSearchRejectionReason } from '../app/bridge-viewer-search-state.js';
import type {
	BridgeFileViewerDisplayModel,
	BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import type {
	BridgeFileViewerRootSnapshot,
	BridgeFileViewerStore,
	BridgeFileViewerStoreActions,
} from './state/bridge-file-viewer-store.js';

interface UseBridgeFileViewerControlEventListenersProps {
	readonly controlProbeSequenceRef: { current: number };
	readonly displayModel: BridgeFileViewerDisplayModel;
	readonly isActive: boolean;
	readonly onSearchResult: (reason: BridgeViewerSearchRejectionReason | null) => void;
	readonly rootSnapshot: BridgeFileViewerRootSnapshot;
	readonly selectFile: (
		selection: BridgeFileViewerSelection,
		source: 'programmatic' | 'user',
	) => void;
	readonly selectedFileId: string | null;
	readonly target: EventTarget;
	readonly viewerActions: BridgeFileViewerStoreActions;
	readonly viewerStore: BridgeFileViewerStore;
}

export function useBridgeFileViewerControlEventListeners(
	props: UseBridgeFileViewerControlEventListenersProps,
): void {
	useLayoutEffect((): (() => void) => {
		if (!props.isActive) return (): void => {};
		const handleControl = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const parsedCommand = bridgeAppControlCommandSchema.safeParse(detail);
			const command = parsedCommand.success
				? parsedCommand.data
				: invalidBridgeAppControlProbeCommand;
			const result = parsedCommand.success
				? applyBridgeFileViewerControlCommand({ command, props })
				: {
						reason: bridgeAppControlCommandRejectionReason(detail),
						status: 'rejected' as const,
					};
			if (command.method === 'bridge.fileTree.search') {
				props.onSearchResult(result.reason === 'search_query_too_long' ? result.reason : null);
			}
			const liveRootSnapshot = props.viewerStore.getState().rootSnapshot;
			publishBridgeAppControlProbe({
				command,
				reason: result.reason,
				sequence: nextBridgeAppControlProbeSequence(props.controlProbeSequenceRef),
				state: {
					categoryFilter: liveRootSnapshot.filterMode,
					filterSurface: 'files',
					gitStatusFilter: 'all',
					renderMode: { kind: 'codeView' },
					selectedItemId: result.selectedItemId ?? props.selectedFileId,
					showBinary: false,
					showLarge: false,
					treeSearchMode: { kind: liveRootSnapshot.search.enteredCriteria.mode },
					treeSearchText: liveRootSnapshot.search.enteredCriteria.query,
				},
				status: result.status,
			});
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		props.target.addEventListener('__bridge_review_control', handleControl);
		if (windowTarget !== null && windowTarget !== props.target) {
			windowTarget.addEventListener('__bridge_review_control', handleControl);
		}
		return (): void => {
			props.target.removeEventListener('__bridge_review_control', handleControl);
			if (windowTarget !== null && windowTarget !== props.target) {
				windowTarget.removeEventListener('__bridge_review_control', handleControl);
			}
		};
	}, [props]);
}

function applyBridgeFileViewerControlCommand(props: {
	readonly command: BridgeAppControlCommand;
	readonly props: UseBridgeFileViewerControlEventListenersProps;
}): {
	readonly reason: string | null;
	readonly selectedItemId?: string;
	readonly status: 'accepted' | 'rejected';
} {
	const command = props.command;
	const controlProps = props.props;
	switch (command.method) {
		case 'bridge.fileTree.search': {
			const transition = controlProps.viewerActions.transitionSearch({
				type: 'apply_semantic_criteria',
				criteria: { query: command.searchText, mode: command.searchMode.kind },
			});
			return transition.rejectionReason === null
				? { reason: null, status: 'accepted' }
				: { reason: transition.rejectionReason, status: 'rejected' };
		}
		case 'bridge.fileTree.setFilter':
			if (command.filter.surface !== 'files') {
				return { reason: 'unsupported_file_filter', status: 'rejected' };
			}
			controlProps.viewerActions.setFilterMode(command.filter.categoryFilter);
			return { reason: null, status: 'accepted' };
		case 'bridge.fileTree.revealPath': {
			const row = controlProps.displayModel.treeRowByPath.get(command.path);
			if (row === undefined || row.isDirectory || row.fileId === null) {
				return { reason: 'path_not_found', status: 'rejected' };
			}
			controlProps.selectFile({ fileId: row.fileId, path: row.path }, 'programmatic');
			return { reason: null, selectedItemId: row.fileId, status: 'accepted' };
		}
		case 'bridge.diff.scrollToFile':
		case 'bridge.diff.expandFile':
		case 'bridge.diff.collapseFile':
		case 'bridge.fileView.showMarkdownPreview':
			return { reason: 'unsupported_surface', status: 'rejected' };
	}
	return assertUnhandledBridgeFileControlCommand(command);
}

function assertUnhandledBridgeFileControlCommand(command: never): never {
	throw new Error(`Unhandled File control command: ${String(command)}`);
}
