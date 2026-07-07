import { useCallback } from 'react';

import type { BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-contracts.js';
import type { BridgeFileViewerRenderState } from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerVisibleDemandControllerProps {
	readonly dispatchVisibleFileViewViewportFact: (props: {
		readonly firstVisibleIndex: number;
		readonly lastVisibleIndex: number;
		readonly renderState: BridgeFileViewerRenderState;
		readonly visibleItemIds: readonly string[];
	}) => void;
	readonly isActive: boolean;
	readonly renderStateRef: { readonly current: BridgeFileViewerRenderState };
}

export function useBridgeFileViewerVisibleDemandController(
	props: UseBridgeFileViewerVisibleDemandControllerProps,
): (change: BridgeFileViewerVisibleFileDemandChange) => void {
	const { dispatchVisibleFileViewViewportFact, isActive, renderStateRef } = props;

	return useCallback(
		(change: BridgeFileViewerVisibleFileDemandChange): void => {
			if (!isActive) {
				return;
			}
			if (change.visibleItemIds.length === 0) {
				return;
			}
			dispatchVisibleFileViewViewportFact({
				firstVisibleIndex: change.firstVisibleIndex,
				lastVisibleIndex: change.lastVisibleIndex,
				renderState: renderStateRef.current,
				visibleItemIds: change.visibleItemIds,
			});
		},
		[dispatchVisibleFileViewViewportFact, isActive, renderStateRef],
	);
}
