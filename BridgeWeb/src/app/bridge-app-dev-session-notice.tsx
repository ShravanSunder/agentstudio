import type { ReactElement } from 'react';

import { BridgeViewerButton } from './bridge-viewer-button.js';

const useDevelopmentTabAction = {
	label: 'Use this tab',
	help: 'Take over the development session from the other tab.',
} as const;

export function BridgeAppDevSessionNotice(props: {
	readonly onTakeOver: () => void;
}): ReactElement {
	return (
		<main
			className="flex h-full min-h-[260px] items-center justify-center bg-background px-8 text-center text-foreground"
			data-testid="bridge-dev-session-inactive"
		>
			<section className="flex max-w-sm flex-col items-center gap-3" role="alert">
				<p className="text-sm font-medium">This development session is active in another tab.</p>
				<p className="text-xs text-muted-foreground">
					Only one tab can use this dev server at a time. This tab has stopped sending requests.
				</p>
				<BridgeViewerButton
					aria-describedby="bridge-dev-tab-takeover-help"
					onClick={props.onTakeOver}
					variant="outline"
				>
					{useDevelopmentTabAction.label}
				</BridgeViewerButton>
				<p className="text-xs text-muted-foreground" id="bridge-dev-tab-takeover-help">
					{useDevelopmentTabAction.help}
				</p>
			</section>
		</main>
	);
}
