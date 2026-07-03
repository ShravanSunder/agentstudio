import { ChevronDownIcon, FolderIcon, SlidersHorizontalIcon, XIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import {
	DropdownMenu,
	DropdownMenuCheckboxItem,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from '../components/ui/dropdown-menu.js';
import { BridgeViewerIcon } from './bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from './bridge-viewer-chrome.js';
import { cn } from './class-name.js';

export interface BridgeViewerFilterOption<TValue extends string> {
	readonly value: TValue;
	readonly label: string;
	readonly selectedLabel?: string;
	readonly icon?: ReactNode;
}

export interface BridgeViewerFilterMenuProps<TValue extends string> {
	readonly label: string;
	readonly value: TValue;
	readonly options: readonly BridgeViewerFilterOption<TValue>[];
	readonly showDefaultOptionInMenu?: boolean;
	readonly testId: string;
	readonly onChange: (value: TValue) => void;
}

export function BridgeViewerFilterMenu<TValue extends string>(
	props: BridgeViewerFilterMenuProps<TValue>,
): ReactElement {
	const selectedOption =
		props.options.find(
			(option: BridgeViewerFilterOption<TValue>): boolean => option.value === props.value,
		) ?? props.options[0];
	const selectedLabel = selectedOption?.selectedLabel ?? selectedOption?.label ?? props.label;
	const clearOption = props.options[0];
	const canClear = clearOption !== undefined && props.value !== clearOption.value;
	const isDefaultSelection = clearOption !== undefined && props.value === clearOption.value;
	const menuOptions =
		props.showDefaultOptionInMenu === false ? props.options.slice(1) : props.options;
	const testIds = bridgeViewerFilterMenuTestIds(props.testId);

	return (
		<DropdownMenu>
			<DropdownMenuTrigger
				aria-label={titleForFilterLabel(props.label)}
				className={cn(
					'flex shrink-0 items-center justify-center gap-0',
					bridgeViewerChromeIconButtonClassName,
					'border border-transparent bg-transparent px-0',
					'text-[12px] text-[var(--bridge-text-secondary)] transition-colors',
					'hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
					'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
					'data-popup-open:bg-[var(--bridge-header-control-active-bg)] data-popup-open:text-[var(--bridge-text-primary)]',
				)}
				data-testid={props.testId}
				title={props.label}
			>
				<span className="relative flex min-w-0 items-center truncate">
					<FilterTriggerGlyph label={props.label} testId={testIds.triggerGlyph} />
					{isDefaultSelection ? null : (
						<span
							className={cn(
								'absolute -right-0.5 -top-0.5 size-1.5 rounded-full',
								'bg-[var(--bridge-focus-border)] shadow-[var(--bridge-focus-dot-shadow)]',
							)}
							data-testid={testIds.activeIndicator}
						/>
					)}
					<span className="sr-only">{selectedLabel}</span>
				</span>
				<BridgeViewerIcon className="sr-only">
					<ChevronDownIcon aria-hidden="true" className="size-3" data-testid={testIds.chevron} />
				</BridgeViewerIcon>
			</DropdownMenuTrigger>
			<DropdownMenuContent
				align="end"
				className={cn(
					'z-[80] w-64 rounded-[10px] border border-[var(--bridge-menu-border)]',
					'max-h-[min(460px,calc(100vh-96px))] bg-[var(--bridge-menu-bg)] p-2',
					'text-[var(--bridge-text-secondary)] shadow-[var(--bridge-menu-shadow)]',
					'ring-1 ring-[var(--bridge-menu-ring)]',
				)}
				data-testid={testIds.popover}
				sideOffset={6}
			>
				<header className="px-2 pb-2 pt-1.5" data-testid={testIds.popoverHeader}>
					<p className="text-[13px] font-medium text-[var(--bridge-text-primary)]">
						{titleForFilterLabel(props.label)}
					</p>
					<p className="mt-0.5 text-[11px] text-[var(--bridge-text-muted)]">
						{descriptionForFilterLabel(props.label)}
					</p>
				</header>
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				{menuOptions.map(
					(option: BridgeViewerFilterOption<TValue>): ReactElement => (
						<DropdownMenuCheckboxItem
							checked={option.value === props.value}
							className={cn(
								'h-8 gap-2 rounded-[7px] px-2 py-0 pr-8 text-[13px]',
								'text-[var(--bridge-text-secondary)] focus:bg-[var(--bridge-list-hover-bg)]',
								'focus:text-[var(--bridge-text-primary)]',
								option.value === props.value && 'text-[var(--bridge-text-primary)]',
							)}
							data-testid={testIds.option}
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
								data-testid={testIds.optionBadge}
							>
								{option.icon ?? option.label.slice(0, 1)}
							</span>
							<span className="min-w-0 truncate" data-testid={testIds.optionLabel}>
								{option.label}
							</span>
						</DropdownMenuCheckboxItem>
					),
				)}
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				<DropdownMenuItem
					className={cn(
						'h-8 gap-2 rounded-[7px] px-2 py-0 text-[13px]',
						'text-[var(--bridge-text-muted)] focus:bg-[var(--bridge-list-hover-bg)]',
						'focus:text-[var(--bridge-text-primary)] data-disabled:cursor-default data-disabled:opacity-55',
					)}
					data-testid={testIds.clear}
					disabled={!canClear}
					onClick={() => {
						if (clearOption !== undefined) {
							props.onChange(clearOption.value);
						}
					}}
				>
					<span className="flex size-5 shrink-0 items-center justify-center rounded-[6px] bg-[var(--bridge-surface-muted-bg)] text-[var(--bridge-text-secondary)]">
						<XIcon aria-hidden="true" className="size-3.5" />
					</span>
					<span>Clear filter</span>
				</DropdownMenuItem>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function FilterTriggerGlyph(props: {
	readonly label: string;
	readonly testId: string;
}): ReactElement {
	if (props.label === 'File class filter') {
		return (
			<FolderIcon
				aria-hidden="true"
				className={cn(bridgeViewerChromeLucideIconClassName, 'text-[var(--bridge-text-secondary)]')}
				data-testid={props.testId}
			/>
		);
	}
	return (
		<SlidersHorizontalIcon
			aria-hidden="true"
			className={cn(bridgeViewerChromeLucideIconClassName, 'text-[var(--bridge-text-secondary)]')}
			data-testid={props.testId}
		/>
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
		return 'Scope the rail without changing metadata';
	}
	return 'Filter visible files';
}

interface BridgeViewerFilterMenuTestIds {
	readonly activeIndicator: string;
	readonly chevron: string;
	readonly clear: string;
	readonly option: string;
	readonly optionBadge: string;
	readonly optionLabel: string;
	readonly popover: string;
	readonly popoverHeader: string;
	readonly triggerGlyph: string;
}

function bridgeViewerFilterMenuTestIds(testId: string): BridgeViewerFilterMenuTestIds {
	return {
		activeIndicator: `${testId}-active-indicator`,
		chevron: `${testId}-chevron`,
		clear: `${testId}-clear`,
		option: `${testId}-option`,
		optionBadge: `${testId}-option-badge`,
		optionLabel: `${testId}-option-label`,
		popover: `${testId}-popover`,
		popoverHeader: `${testId}-popover-header`,
		triggerGlyph: `${testId}-trigger-glyph`,
	};
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
