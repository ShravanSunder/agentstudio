import { SearchIcon } from 'lucide-react';
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
					'h-7 w-7 rounded-md border-transparent bg-transparent px-0',
					props.value.length > 0 && 'text-[var(--bridge-text-primary)]',
				)}
				onClick={focusSiblingSearchInput}
				testId="bridge-review-search-toggle"
				title="Search files"
			>
				<BridgeReviewIcon>
					<SearchIcon aria-hidden="true" className="size-4" />
				</BridgeReviewIcon>
			</BridgeReviewButton>
			<Input
				aria-label="Search files"
				autoComplete="off"
				className={cn(
					'h-7 w-0 min-w-0 shrink-0 rounded-md border border-transparent px-0',
					'bg-[var(--bridge-surface-raised-bg)] text-[12px] text-[var(--bridge-text-primary)]',
					'pointer-events-none opacity-0 outline-none transition-[width,opacity,border-color,padding]',
					'placeholder:text-[var(--bridge-text-muted)]',
					'focus:pointer-events-auto focus:w-36 focus:border-[var(--bridge-accent)] focus:px-2 focus:opacity-100',
					'group-focus-within/search:pointer-events-auto group-focus-within/search:w-36 group-focus-within/search:border-[var(--bridge-border-opaque)] group-focus-within/search:px-2 group-focus-within/search:opacity-100',
					props.value.length > 0 &&
						'pointer-events-auto w-36 border-[var(--bridge-border-opaque)] px-2 opacity-100',
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
