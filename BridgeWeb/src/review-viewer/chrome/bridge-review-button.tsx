import type { MouseEvent, ReactElement, ReactNode } from 'react';

import { cn } from '../../app/class-name.js';
import { Button } from '../../components/ui/button.js';

export interface BridgeReviewButtonProps {
	readonly children: ReactNode;
	readonly ariaLabel?: string;
	readonly ariaPressed?: boolean;
	readonly className?: string;
	readonly 'data-testid'?: string;
	readonly disabled?: boolean;
	readonly testId?: string;
	readonly title?: string;
	readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
}

export function BridgeReviewButton(props: BridgeReviewButtonProps): ReactElement {
	return (
		<Button
			aria-label={props.ariaLabel}
			aria-pressed={props.ariaPressed}
			className={cn(
				'h-6 shrink-0 gap-1 rounded-[5px] px-1.5 text-[11px] leading-none',
				'text-[var(--bridge-text-secondary)] transition-colors',
				'hover:bg-[var(--bridge-surface-raised-bg)] hover:text-[var(--bridge-text-primary)]',
				'focus-visible:border-[var(--bridge-accent)] focus-visible:outline-none',
				props.ariaPressed === true &&
					'bg-[var(--bridge-accent-soft)] text-[var(--bridge-text-primary)]',
				props.className,
			)}
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

export interface BridgeReviewIconProps {
	readonly children: ReactNode;
}

export function BridgeReviewIcon(props: BridgeReviewIconProps): ReactElement {
	return (
		<span
			aria-hidden="true"
			className="inline-flex size-3 shrink-0 items-center justify-center text-[10px] leading-none"
		>
			{props.children}
		</span>
	);
}
