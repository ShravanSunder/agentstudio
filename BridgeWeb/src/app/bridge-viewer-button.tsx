import type { MouseEvent, ReactElement, ReactNode } from 'react';

import { Button } from '../components/ui/button.js';
import {
	bridgeViewerChromeButtonClassName,
	bridgeViewerChromeIconClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export interface BridgeViewerButtonProps {
	readonly children: ReactNode;
	readonly ariaLabel?: string;
	readonly ariaPressed?: boolean;
	readonly className?: string;
	readonly 'data-bridge-viewer-context-selected'?: string;
	readonly 'data-bridge-viewer-context-target'?: string;
	readonly 'data-testid'?: string;
	readonly disabled?: boolean;
	readonly testId?: string;
	readonly title?: string;
	readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
}

export function BridgeViewerButton(props: BridgeViewerButtonProps): ReactElement {
	return (
		<Button
			aria-label={props.ariaLabel}
			aria-pressed={props.ariaPressed}
			className={cn(
				bridgeViewerChromeButtonClassName,
				'gap-1 px-1.5',
				'text-[var(--bridge-text-secondary)] transition-colors',
				'hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
				'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
				props.ariaPressed === true &&
					'border-transparent bg-[var(--bridge-header-control-active-bg)] text-[var(--bridge-text-primary)]',
				props.className,
			)}
			data-bridge-viewer-context-selected={props['data-bridge-viewer-context-selected']}
			data-bridge-viewer-context-target={props['data-bridge-viewer-context-target']}
			data-testid={props.testId ?? props['data-testid']}
			disabled={props.disabled}
			onClick={props.onClick}
			size="sm"
			title={props.title}
			type="button"
			variant="ghost"
		>
			{props.children}
		</Button>
	);
}

export interface BridgeViewerIconProps {
	readonly children: ReactNode;
	readonly className?: string;
}

export function BridgeViewerIcon(props: BridgeViewerIconProps): ReactElement {
	return (
		<span aria-hidden="true" className={cn(bridgeViewerChromeIconClassName, props.className)}>
			{props.children}
		</span>
	);
}
