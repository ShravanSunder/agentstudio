import type { ChangeEvent, MouseEvent, ReactElement } from 'react';

import { cn } from '../../app/class-name.js';
import { Input } from '../../components/ui/input.js';
import { BridgeReviewButton, BridgeReviewIcon } from './bridge-review-button.js';

export interface BridgeReviewSearchControlProps {
	readonly value: string;
	readonly onChange: (value: string) => void;
}

export function BridgeReviewSearchControl(props: BridgeReviewSearchControlProps): ReactElement {
	return (
		<div
			className="group/search relative flex min-w-0 items-center"
			data-testid="bridge-review-search-control"
		>
			<BridgeReviewButton
				ariaLabel="Search files"
				className={cn(
					'h-8 w-8 rounded-[7px] border-[var(--bridge-border-subtle)]',
					'bg-[var(--bridge-canvas-bg)] px-0',
					props.value.length > 0 && 'text-[var(--bridge-text-primary)]',
				)}
				onClick={focusSiblingSearchInput}
				testId="bridge-review-search-toggle"
				title="Search files"
			>
				<BridgeReviewIcon>
					<svg aria-hidden="true" className="size-4" viewBox="0 0 16 16">
						<circle cx="7" cy="7" fill="none" r="4.5" stroke="currentColor" strokeWidth="1.5" />
						<path
							d="m10.5 10.5 3 3"
							stroke="currentColor"
							strokeLinecap="round"
							strokeWidth="1.5"
						/>
					</svg>
				</BridgeReviewIcon>
			</BridgeReviewButton>
			<Input
				aria-label="Search files"
				autoComplete="off"
				className={cn(
					'absolute right-0 top-[calc(100%+4px)] z-50 h-8 w-56 min-w-0',
					'rounded-[7px] border border-[var(--bridge-border-opaque)]',
					'bg-[var(--bridge-canvas-bg)] px-2 text-[12px] text-[var(--bridge-text-primary)]',
					'pointer-events-none opacity-0 shadow-[0_18px_48px_rgb(0_0_0_/_0.52)]',
					'outline-none transition-opacity placeholder:text-[var(--bridge-text-muted)]',
					'focus:pointer-events-auto focus:opacity-100 focus:border-[var(--bridge-accent)]',
					'group-focus-within/search:pointer-events-auto group-focus-within/search:opacity-100',
					props.value.length > 0 && 'pointer-events-auto opacity-100',
				)}
				data-testid="bridge-review-search-input"
				onChange={(event: ChangeEvent<HTMLInputElement>): void =>
					props.onChange(event.target.value)
				}
				placeholder="Search..."
				role="searchbox"
				type="text"
				value={props.value}
			/>
		</div>
	);
}

function focusSiblingSearchInput(event: MouseEvent<HTMLButtonElement>): void {
	const searchInput =
		event.currentTarget.parentElement?.querySelector<HTMLInputElement>('input[role="searchbox"]');
	searchInput?.focus();
}
