import type { ReactElement, ReactNode } from 'react';

import { cn } from '../../app/class-name.js';
import {
	DropdownMenu,
	DropdownMenuCheckboxItem,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from '../../components/ui/dropdown-menu.js';
import { BridgeReviewIcon } from './bridge-review-button.js';

export interface BridgeReviewFilterOption<TValue extends string> {
	readonly value: TValue;
	readonly label: string;
	readonly selectedLabel?: string;
	readonly icon?: ReactNode;
}

export interface BridgeReviewFilterMenuProps<TValue extends string> {
	readonly label: string;
	readonly value: TValue;
	readonly options: readonly BridgeReviewFilterOption<TValue>[];
	readonly showDefaultOptionInMenu?: boolean;
	readonly testId: string;
	readonly onChange: (value: TValue) => void;
}

export function BridgeReviewFilterMenu<TValue extends string>(
	props: BridgeReviewFilterMenuProps<TValue>,
): ReactElement {
	const selectedOption =
		props.options.find(
			(option: BridgeReviewFilterOption<TValue>): boolean => option.value === props.value,
		) ?? props.options[0];
	const selectedLabel = selectedOption?.selectedLabel ?? selectedOption?.label ?? props.label;
	const clearOption = props.options[0];
	const canClear = clearOption !== undefined && props.value !== clearOption.value;
	const isDefaultSelection = clearOption !== undefined && props.value === clearOption.value;
	const menuOptions =
		props.showDefaultOptionInMenu === false ? props.options.slice(1) : props.options;

	return (
		<DropdownMenu>
			<DropdownMenuTrigger
				aria-label={titleForFilterLabel(props.label)}
				className={cn(
					'flex h-8 w-9 shrink-0 items-center justify-center gap-0 rounded-[7px]',
					'border border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-raised-bg)] px-0',
					'text-[12px] text-[var(--bridge-text-secondary)] transition-colors',
					'shadow-[inset_0_0_0_1px_rgb(255_255_255_/_0.02)]',
					'hover:bg-[var(--bridge-accent-soft)] hover:text-[var(--bridge-text-primary)]',
					'focus-visible:border-[var(--bridge-accent)] focus-visible:outline-none',
					'data-popup-open:bg-[var(--bridge-accent-soft)] data-popup-open:text-[var(--bridge-text-primary)]',
				)}
				data-testid={props.testId}
				title={props.label}
			>
				<span className="relative flex min-w-0 items-center truncate">
					<FilterTriggerGlyph label={props.label} />
					{isDefaultSelection ? null : (
						<span
							className={cn(
								'absolute -right-0.5 -top-0.5 size-1.5 rounded-full',
								'bg-[var(--bridge-accent)] shadow-[0_0_0_1px_var(--bridge-surface-raised-bg)]',
							)}
							data-testid="bridge-review-filter-active-indicator"
						/>
					)}
					<span className="sr-only">{selectedLabel}</span>
				</span>
				<BridgeReviewIcon>
					<svg
						aria-hidden="true"
						className="size-3"
						data-testid="bridge-review-filter-chevron"
						viewBox="0 0 16 16"
					>
						<path
							d="m4.5 6.25 3.5 3.5 3.5-3.5"
							fill="none"
							stroke="currentColor"
							strokeLinecap="round"
							strokeLinejoin="round"
							strokeWidth="1.6"
						/>
					</svg>
				</BridgeReviewIcon>
			</DropdownMenuTrigger>
			<DropdownMenuContent
				align="end"
				className={cn(
					'z-[80] w-64 rounded-[10px] border border-[rgb(137_180_250_/_0.28)]',
					'max-h-[min(460px,calc(100vh-96px))] bg-[var(--bridge-menu-bg)] p-2',
					'text-[var(--bridge-text-secondary)] shadow-[0_24px_68px_rgb(0_0_0_/_0.86)]',
					'ring-1 ring-[rgb(205_214_244_/_0.16)]',
				)}
				data-testid="bridge-review-filter-popover"
				sideOffset={6}
			>
				<header className="px-2 pb-2 pt-1.5" data-testid="bridge-review-filter-popover-header">
					<p className="text-[13px] font-medium text-[var(--bridge-text-primary)]">
						{titleForFilterLabel(props.label)}
					</p>
					<p className="mt-0.5 text-[11px] text-[var(--bridge-text-muted)]">
						{descriptionForFilterLabel(props.label)}
					</p>
				</header>
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				{menuOptions.map(
					(option: BridgeReviewFilterOption<TValue>): ReactElement => (
						<DropdownMenuCheckboxItem
							checked={
								option.value === props.value ||
								(props.showDefaultOptionInMenu === false && isDefaultSelection)
							}
							className={cn(
								'h-8 gap-2 rounded-[7px] px-2 py-0 pr-8 text-[13px]',
								'text-[var(--bridge-text-secondary)] focus:bg-[var(--bridge-accent-soft)]',
								'focus:text-[var(--bridge-text-primary)]',
								option.value === props.value && 'text-[var(--bridge-text-primary)]',
							)}
							data-testid="bridge-review-filter-option"
							key={option.value}
							onClick={() => props.onChange(option.value)}
						>
							<span
								className={cn(
									'flex size-5 shrink-0 items-center justify-center rounded-[6px]',
									'text-[10px] font-semibold leading-none',
									statusBadgeClassName(option.value),
								)}
								aria-hidden="true"
								data-testid="bridge-review-filter-option-badge"
							>
								{option.icon ?? option.label.slice(0, 1)}
							</span>
							<span className="min-w-0 truncate">{option.label}</span>
						</DropdownMenuCheckboxItem>
					),
				)}
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				<DropdownMenuItem
					className={cn(
						'h-8 gap-2 rounded-[7px] px-2 py-0 text-[13px]',
						'text-[var(--bridge-text-muted)] focus:bg-[var(--bridge-accent-soft)]',
						'focus:text-[var(--bridge-text-primary)] data-disabled:cursor-default data-disabled:opacity-55',
					)}
					data-testid="bridge-review-filter-clear"
					disabled={!canClear}
					onClick={() => {
						if (clearOption !== undefined) {
							props.onChange(clearOption.value);
						}
					}}
				>
					<span className="flex size-5 shrink-0 items-center justify-center rounded-[6px] bg-[var(--bridge-surface-muted-bg)] text-[var(--bridge-text-secondary)]">
						<svg aria-hidden="true" className="size-3.5" viewBox="0 0 16 16">
							<path
								d="m4.5 4.5 7 7m0-7-7 7"
								fill="none"
								stroke="currentColor"
								strokeLinecap="round"
								strokeWidth="1.8"
							/>
						</svg>
					</span>
					<span>Clear filter</span>
				</DropdownMenuItem>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function FilterTriggerGlyph(props: { readonly label: string }): ReactElement {
	if (props.label === 'File class filter') {
		return (
			<svg
				aria-hidden="true"
				className="size-4 text-[var(--bridge-text-secondary)]"
				data-testid="bridge-review-filter-trigger-glyph"
				viewBox="0 0 16 16"
			>
				<path
					d="M2.75 4.5h4l1 1h5.5v6.75H2.75z"
					fill="none"
					stroke="currentColor"
					strokeLinejoin="round"
					strokeWidth="1.4"
				/>
			</svg>
		);
	}
	return (
		<svg
			aria-hidden="true"
			className="size-4 text-[var(--bridge-text-secondary)]"
			data-testid="bridge-review-filter-trigger-glyph"
			viewBox="0 0 16 16"
		>
			<path
				d="M3 4h10M5.5 8h5M7 12h2"
				fill="none"
				stroke="currentColor"
				strokeLinecap="round"
				strokeWidth="1.5"
			/>
		</svg>
	);
}

function titleForFilterLabel(label: string): string {
	if (label === 'Git status filter') {
		return 'Filter by Git status';
	}
	if (label === 'File class filter') {
		return 'Filter by file class';
	}
	return label;
}

function descriptionForFilterLabel(label: string): string {
	if (label === 'Git status filter') {
		return 'Option-click to isolate one status';
	}
	if (label === 'File class filter') {
		return 'Scope the rail without changing the review package';
	}
	return 'Filter the visible review files';
}

function statusBadgeClassName(value: string): string {
	switch (value) {
		case 'added':
		case 'source':
			return 'bg-[color-mix(in_oklch,var(--bridge-added)_18%,transparent)] text-[var(--bridge-added)]';
		case 'modified':
		case 'fixture':
			return 'bg-[color-mix(in_oklch,var(--bridge-accent)_18%,transparent)] text-[var(--bridge-accent)]';
		case 'renamed':
		case 'test':
		case 'docs':
			return 'bg-[color-mix(in_oklch,var(--bridge-warning)_20%,transparent)] text-[var(--bridge-warning)]';
		case 'deleted':
		case 'binary':
			return 'bg-[color-mix(in_oklch,var(--bridge-deleted)_18%,transparent)] text-[var(--bridge-deleted)]';
		case 'copied':
		case 'generated':
		case 'vendor':
		case 'config':
			return 'bg-[color-mix(in_oklch,var(--bridge-text-muted)_18%,transparent)] text-[var(--bridge-text-secondary)]';
		default:
			return 'bg-[color-mix(in_oklch,var(--bridge-text-muted)_18%,transparent)] text-[var(--bridge-text-secondary)]';
	}
}
