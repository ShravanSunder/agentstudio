import type { ReactElement, ReactNode } from 'react';

import type { BridgePageReadyError } from '../bridge/bridge-page-handshake.js';
import type { BridgePaneReloadPort } from './bridge-pane-reload-port.js';
import { BridgeRegionPresentation } from './bridge-region-presentation.js';

export function BridgeViewerAppShell(props: {
	readonly appOwner: 'BridgeApp';
	readonly children: ReactNode;
	readonly mode: 'file' | 'review';
	readonly pageReadyFailure?: BridgePageReadyError | null;
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
				region="pane-start"
				shape="code"
				keepContentMounted
				{...(props.paneReloadPort === undefined ? {} : { paneReloadPort: props.paneReloadPort })}
				state={
					props.pageReadyFailure == null
						? { kind: 'content' }
						: {
								kind: 'failed',
								retainsContent: false,
								failure: { kind: 'retryable', scope: 'pane', message: 'Bridge failed to start' },
							}
				}
			>
				<div className="relative h-full min-h-0">{props.children}</div>
			</BridgeRegionPresentation>
		</div>
	);
}
