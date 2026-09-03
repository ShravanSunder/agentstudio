import type { KeyboardEvent, ReactElement, ReactNode } from 'react';

import { cn } from './class-name.js';

export const bridgeViewerActionToolbarSurfaceClassName =
	'border-b border-[var(--bridge-border-subtle)] bg-card px-2 py-1.5 shadow-[var(--bridge-divider-shadow)]';

export function BridgeViewerActionToolbar(props: {
	readonly ariaLabel: string;
	readonly children: ReactNode;
	readonly className?: string;
	readonly onKeyDown?: (event: KeyboardEvent<HTMLElement>) => void;
	readonly testId?: string;
}): ReactElement {
	return (
		<section
			aria-label={props.ariaLabel}
			className={cn(
				'flex min-h-9 w-full flex-wrap items-center gap-1.5',
				bridgeViewerActionToolbarSurfaceClassName,
				props.className,
			)}
			data-bridge-viewer-action-toolbar="true"
			data-testid={props.testId}
			onKeyDown={props.onKeyDown}
		>
			{props.children}
		</section>
	);
}
