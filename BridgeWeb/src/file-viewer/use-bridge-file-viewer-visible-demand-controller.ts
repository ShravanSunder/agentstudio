import { useCallback } from 'react';

import type { BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-contracts.js';
interface UseBridgeFileViewerVisibleDemandControllerProps {
	readonly dispatchVisibleFileViewViewportFact: (props: {
		readonly firstVisibleIndex: number;
		readonly lastVisibleIndex: number;
		readonly visibleItemIds: readonly string[];
	}) => void;
	readonly isActive: boolean;
}

export function useBridgeFileViewerVisibleDemandController(
	props: UseBridgeFileViewerVisibleDemandControllerProps,
): (change: BridgeFileViewerVisibleFileDemandChange) => void {
	const { dispatchVisibleFileViewViewportFact, isActive } = props;

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
				visibleItemIds: change.visibleItemIds,
			});
		},
		[dispatchVisibleFileViewViewportFact, isActive],
	);
}
