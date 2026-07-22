import { useEffect } from 'react';

import type { BridgeFileViewerDisplaySource } from './bridge-file-viewer-display-model.js';

export function useBridgeFileViewerDisplaySourceReporter(props: {
	readonly onDisplaySourceChange?: (source: BridgeFileViewerDisplaySource | null) => void;
	readonly source: BridgeFileViewerDisplaySource | null;
}): void {
	const { onDisplaySourceChange } = props;
	const sourceGeneration = props.source?.generation ?? null;
	const sourceId = props.source?.sourceId ?? null;
	useEffect((): void => {
		onDisplaySourceChange?.(
			sourceGeneration === null || sourceId === null
				? null
				: { generation: sourceGeneration, sourceId },
		);
	}, [onDisplaySourceChange, sourceGeneration, sourceId]);
}
