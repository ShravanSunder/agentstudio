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
	const {
		activeVisibleDemandSignatureRef,
		appliedNavigationCommandIdRef,
		demandDispatchRequestIdRef,
		isActive,
		onDeactivateOpenFileWork,
		openFileRequestIdRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		pendingSelectedDescriptorRequestRef,
		pendingStaleRefreshDescriptorRequestKeyRef,
		recentlyUpdatedDemandInFlightRef,
		recentlyUpdatedDemandRequestIdRef,
		recentlyUpdatedLoadedDescriptorIdRef,
	} = props;
	const activeModeTokenRef = useRef(0);
	const isActiveRef = useRef(isActive);

	useLayoutEffect((): void => {
		if (isActiveRef.current === isActive) {
			return;
		}
		isActiveRef.current = isActive;
		activeModeTokenRef.current += 1;
		if (isActive) {
			return;
		}
		activeVisibleDemandSignatureRef.current = null;
		demandDispatchRequestIdRef.current += 1;
		openFileRequestIdRef.current += 1;
		recentlyUpdatedDemandRequestIdRef.current += 1;
		appliedNavigationCommandIdRef.current = null;
		pendingRecentlyUpdatedDescriptorDemandRef.current = null;
		pendingSelectedDescriptorRequestRef.current = null;
		pendingStaleRefreshDescriptorRequestKeyRef.current = null;
		recentlyUpdatedDemandInFlightRef.current = false;
		recentlyUpdatedLoadedDescriptorIdRef.current = null;
		onDeactivateOpenFileWork();
	}, [
		activeVisibleDemandSignatureRef,
		appliedNavigationCommandIdRef,
		demandDispatchRequestIdRef,
		isActive,
		onDeactivateOpenFileWork,
		openFileRequestIdRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		pendingSelectedDescriptorRequestRef,
		pendingStaleRefreshDescriptorRequestKeyRef,
		recentlyUpdatedDemandInFlightRef,
		recentlyUpdatedDemandRequestIdRef,
		recentlyUpdatedLoadedDescriptorIdRef,
	]);

	return { activeModeTokenRef, isActiveRef };
}
