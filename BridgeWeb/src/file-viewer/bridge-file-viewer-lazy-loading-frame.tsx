import type { ReactElement, ReactNode } from 'react';

import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import { BridgeViewerResizableRailLayout } from '../app/bridge-viewer-resizable-rail-layout.js';

export function BridgeFileViewerLazyLoadingFrame(props: {
	readonly isActive?: boolean | undefined;
	readonly viewerHeaderControls?: ReactNode;
}): ReactElement {
	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)]"
			data-testid="bridge-file-viewer-lazy-loading-frame"
		>
			<BridgeViewerResizableRailLayout
				autosaveId="bridge-viewer-right-rail"
				isActive={props.isActive}
				content={
					<section className="grid h-full min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] overflow-hidden">
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
				}
				contentTestId="bridge-file-viewer-content-panel"
				handleTestId="bridge-file-viewer-rail-resize-handle"
				rail={
					<aside
						className="h-full min-h-0 min-w-0 border-l border-[var(--bridge-border-opaque)] bg-[var(--bridge-surface-bg)]"
						data-testid="bridge-file-viewer-lazy-loading-sidebar"
					/>
				}
				railTestId="bridge-file-viewer-resizable-rail"
			/>
		</main>
	);
}
