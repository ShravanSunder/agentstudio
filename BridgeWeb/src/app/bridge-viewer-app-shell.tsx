import type { ReactElement, ReactNode } from 'react';

export function BridgeViewerAppShell(props: {
	readonly appOwner: 'BridgeApp';
	readonly children: ReactNode;
	readonly mode: 'file' | 'review';
}): ReactElement {
	return (
		<div
			className="dark relative h-screen min-h-screen w-full overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)] antialiased"
			data-bridge-app-owner={props.appOwner}
			data-bridge-viewer-mode={props.mode}
			data-bridge-viewer-shell-owner="BridgeViewerAppShell"
			data-testid="bridge-app-root"
		>
			{props.children}
		</div>
	);
}
