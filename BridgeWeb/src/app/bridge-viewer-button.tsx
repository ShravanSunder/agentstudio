import type { ComponentProps, ReactElement, ReactNode, Ref } from 'react';

import { Button } from '../components/ui/button.js';
import {
	bridgeViewerChromeButtonClassName,
	bridgeViewerChromeIconClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export interface BridgeViewerButtonProps extends Omit<
	ComponentProps<typeof Button>,
	'children' | 'className' | 'ref' | 'size' | 'variant'
> {
	readonly children?: ReactNode;
	readonly buttonRef?: Ref<HTMLButtonElement>;
	readonly ariaLabel?: string;
	readonly ariaPressed?: boolean;
	readonly className?: string;
	readonly 'data-bridge-viewer-context-selected'?: string;
	readonly 'data-bridge-viewer-context-target'?: string;
	readonly 'data-testid'?: string;
	readonly testId?: string;
}

export const bridgeViewerButtonClassName = cn(
	bridgeViewerChromeButtonClassName,
	'gap-1 px-1.5',
	'text-[var(--bridge-text-secondary)] transition-colors',
	'hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
	'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
);

export function BridgeViewerButton(props: BridgeViewerButtonProps): ReactElement {
	const { ariaLabel, ariaPressed, buttonRef, children, className, testId, ...buttonProps } = props;
	return (
		<Button
			{...buttonProps}
			ref={buttonRef}
			aria-label={ariaLabel ?? buttonProps['aria-label']}
			aria-pressed={ariaPressed ?? buttonProps['aria-pressed']}
			className={cn(
				bridgeViewerButtonClassName,
				ariaPressed === true &&
					'border-transparent bg-[var(--bridge-header-control-active-bg)] text-[var(--bridge-text-primary)]',
				className,
			)}
			data-bridge-viewer-context-selected={props['data-bridge-viewer-context-selected']}
			data-bridge-viewer-context-target={props['data-bridge-viewer-context-target']}
			data-testid={testId ?? props['data-testid']}
			size="sm"
			type="button"
			variant="ghost"
		>
			{children}
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
