import { useLayoutEffect, useRef, type MutableRefObject } from 'react';

import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand } from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerActiveModeGateProps {
	readonly activeVisibleDemandSignatureRef: MutableRefObject<string | null>;
	readonly appliedNavigationCommandIdRef: MutableRefObject<string | null>;
	readonly demandDispatchRequestIdRef: MutableRefObject<number>;
	readonly isActive: boolean;
	readonly onDeactivateOpenFileWork: () => void;
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly pendingRecentlyUpdatedDescriptorDemandRef: MutableRefObject<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>;
	readonly pendingSelectedDescriptorRequestRef: MutableRefObject<WorktreeFileDescriptorRequest | null>;
	readonly pendingStaleRefreshDescriptorRequestKeyRef: MutableRefObject<string | null>;
	readonly recentlyUpdatedDemandInFlightRef: MutableRefObject<boolean>;
	readonly recentlyUpdatedLoadedDescriptorIdRef: MutableRefObject<string | null>;
	readonly recentlyUpdatedDemandRequestIdRef: MutableRefObject<number>;
}

export interface BridgeFileViewerActiveModeGate {
	readonly activeModeTokenRef: MutableRefObject<number>;
	readonly isActiveRef: MutableRefObject<boolean>;
}

export function useBridgeFileViewerActiveModeGate(
	props: UseBridgeFileViewerActiveModeGateProps,
): BridgeFileViewerActiveModeGate {
	const activeModeTokenRef = useRef(0);
	const isActiveRef = useRef(props.isActive);

	useLayoutEffect((): void => {
		if (isActiveRef.current === props.isActive) {
			return;
		}
		isActiveRef.current = props.isActive;
		activeModeTokenRef.current += 1;
		if (props.isActive) {
			return;
		}
		props.activeVisibleDemandSignatureRef.current = null;
		props.demandDispatchRequestIdRef.current += 1;
		props.openFileRequestIdRef.current += 1;
		props.recentlyUpdatedDemandRequestIdRef.current += 1;
		props.appliedNavigationCommandIdRef.current = null;
		props.pendingRecentlyUpdatedDescriptorDemandRef.current = null;
		props.pendingSelectedDescriptorRequestRef.current = null;
		props.pendingStaleRefreshDescriptorRequestKeyRef.current = null;
		props.recentlyUpdatedDemandInFlightRef.current = false;
		props.recentlyUpdatedLoadedDescriptorIdRef.current = null;
		props.onDeactivateOpenFileWork();
	}, [
		props.activeVisibleDemandSignatureRef,
		props.appliedNavigationCommandIdRef,
		props.demandDispatchRequestIdRef,
		props.isActive,
		props.onDeactivateOpenFileWork,
		props.openFileRequestIdRef,
		props.pendingRecentlyUpdatedDescriptorDemandRef,
		props.pendingSelectedDescriptorRequestRef,
		props.pendingStaleRefreshDescriptorRequestKeyRef,
		props.recentlyUpdatedDemandInFlightRef,
		props.recentlyUpdatedLoadedDescriptorIdRef,
		props.recentlyUpdatedDemandRequestIdRef,
	]);

	return { activeModeTokenRef, isActiveRef };
}
