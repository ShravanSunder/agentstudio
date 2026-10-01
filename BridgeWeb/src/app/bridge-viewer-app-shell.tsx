import type { ReactElement, ReactNode } from 'react';

import type { BridgePaneFailedStartFact } from '../core/models/bridge-pane-failed-start.js';
import { bridgePaneFailedStartDisplaySpec } from './bridge-pane-failed-start-presentation.js';
import type { BridgePaneReloadPort } from './bridge-pane-reload-port.js';
import { BridgeRegionPresentation } from './bridge-region-presentation.js';

export function BridgeViewerAppShell(props: {
	readonly appOwner: 'BridgeApp';
	readonly children: ReactNode;
	readonly mode: 'file' | 'review';
	readonly paneFailedStart?: BridgePaneFailedStartFact | null;
	readonly retainsContent?: boolean;
	readonly paneReloadPort?: BridgePaneReloadPort;
}): ReactElement {
	return (
		<div
			className="relative h-screen min-h-screen w-full overflow-hidden bg-background text-foreground antialiased"
			data-bridge-app-owner={props.appOwner}
			data-bridge-viewer-mode={props.mode}
			data-bridge-viewer-shell-owner="BridgeViewerAppShell"
			data-testid="bridge-app-root"
		>
			<BridgeRegionPresentation
				failureControl="primary"
				region="pane-start"
				shape="code"
				keepContentMounted
				{...(props.paneReloadPort === undefined ? {} : { paneReloadPort: props.paneReloadPort })}
				state={
					props.paneFailedStart == null
						? { kind: 'content' }
						: {
								kind: 'failed',
								retainsContent: props.retainsContent ?? false,
								failure: {
									kind: 'retryable',
									scope: 'pane',
									message: bridgePaneFailedStartDisplaySpec.message,
								},
							}
				}
			>
				<div className="relative h-full min-h-0">{props.children}</div>
			</BridgeRegionPresentation>
		</div>
	);
}
