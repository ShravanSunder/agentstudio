import type { ReactElement } from 'react';

import { BridgeViewerButton } from './bridge-viewer-button.js';

const refreshDevelopmentTabAction = {
	label: 'Refresh',
	help: 'Close the other tab, then refresh this page.',
} as const;

export function BridgeAppDevSessionNotice(props: { readonly onRefresh: () => void }): ReactElement {
	return (
		<main
			className="flex h-full min-h-[260px] items-center justify-center bg-background px-8 text-center text-foreground"
			data-testid="bridge-dev-session-inactive"
		>
			<section className="flex max-w-sm flex-col items-center gap-3" role="alert">
				<p className="text-sm font-medium">This dev server is open elsewhere.</p>
				<p className="text-xs text-muted-foreground">{refreshDevelopmentTabAction.help}</p>
				<BridgeViewerButton onClick={props.onRefresh}>
					{refreshDevelopmentTabAction.label}
				</BridgeViewerButton>
			</section>
		</main>
	);
}
