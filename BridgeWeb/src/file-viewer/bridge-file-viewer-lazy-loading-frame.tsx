import type { ReactElement, ReactNode } from 'react';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';

export function BridgeFileViewerLazyLoadingFrame(props: {
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<main
			className="grid h-full min-h-0 w-full grid-cols-[minmax(0,1fr)_minmax(260px,340px)] overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)]"
			data-testid="bridge-file-viewer-lazy-loading-frame"
		>
			<section className="grid min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] overflow-hidden">
				<BridgeViewerContentHeader
					controls={props.viewerHeaderControls}
					eyebrow="Files"
					title="Loading file view"
				/>
				<section
					className="min-h-0 min-w-0 bg-[var(--bridge-canvas-bg)]"
					data-testid="bridge-file-viewer-lazy-loading-canvas"
				/>
			</section>
			<aside
				className="order-last min-h-0 min-w-0 border-l border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)]"
				data-testid="bridge-file-viewer-lazy-loading-sidebar"
			/>
		</main>
	);
}
