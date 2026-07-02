import type { AriaRole, ReactElement, ReactNode } from 'react';

import { bridgeViewerChromeToolbarClassName } from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export interface BridgeViewerRailToolbarProps {
	readonly className?: string;
	readonly leading: ReactNode;
	readonly leadingAriaLive?: 'off' | 'polite' | 'assertive';
	readonly leadingClassName?: string;
	readonly leadingRole?: AriaRole;
	readonly leadingTestId: string;
	readonly testId: string;
	readonly trailing: ReactNode;
	readonly trailingClassName?: string;
	readonly trailingTestId: string;
}

export function BridgeViewerRailToolbar(props: BridgeViewerRailToolbarProps): ReactElement {
	return (
		<div
			className={cn(
				'flex shrink-0 items-center justify-between gap-1',
				bridgeViewerChromeToolbarClassName,
				props.className,
			)}
			data-bridge-shared-rail-toolbar="true"
			data-testid={props.testId}
		>
			<div
				aria-live={props.leadingAriaLive}
				className={cn('flex min-w-0 items-center gap-1', props.leadingClassName)}
				data-testid={props.leadingTestId}
				role={props.leadingRole}
			>
				{props.leading}
			</div>
			<div
				className={cn('flex min-w-0 items-center justify-end gap-1', props.trailingClassName)}
				data-testid={props.trailingTestId}
			>
				{props.trailing}
			</div>
		</div>
	);
}
