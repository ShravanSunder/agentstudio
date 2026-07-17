import { FolderIcon, XIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import {
	BridgeViewerFilterTrigger,
	bridgeViewerFilterClearClassName,
	bridgeViewerFilterMenuSurfaceClassName,
	bridgeViewerFilterOptionClassName,
} from '../../app/bridge-viewer-filter-menu.js';
import { cn } from '../../app/class-name.js';
import {
	DropdownMenu,
	DropdownMenuCheckboxItem,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
} from '../../components/ui/dropdown-menu.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
} from '../../foundation/review-package/bridge-review-package.js';

export interface BridgeReviewFacetMenuOption<TValue extends string> {
	readonly value: TValue;
	readonly label: string;
	readonly description: string;
	readonly icon?: ReactNode;
}

export interface BridgeReviewFacetMenuProps {
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
	readonly gitStatusOptions: readonly BridgeReviewFacetMenuOption<BridgeFileChangeKind | 'all'>[];
	readonly fileClassOptions: readonly BridgeReviewFacetMenuOption<BridgeFileClass | 'all'>[];
	readonly onGitStatusFilterChange: (status: BridgeFileChangeKind | 'all') => void;
	readonly onFileClassFilterChange: (fileClass: BridgeFileClass | 'all') => void;
}

export function BridgeReviewFacetMenu(props: BridgeReviewFacetMenuProps): ReactElement {
	const hasActiveGitFilter = props.gitStatusFilter !== 'all';
	const hasActiveFileClassFilter = props.fileClassFilter !== 'all';
	const hasActiveFacet = hasActiveGitFilter || hasActiveFileClassFilter;

	return (
		<DropdownMenu>
			<BridgeViewerFilterTrigger
				activeIndicatorTestId="bridge-review-facet-active-indicator"
				hasActiveFilter={hasActiveFacet}
				label="Filter review files"
				selectedLabel="Review filters"
				testId="bridge-review-facet-menu-control"
				triggerGlyphTestId="bridge-review-facet-trigger-glyph"
			/>
			<DropdownMenuContent
				align="end"
				className={cn(bridgeViewerFilterMenuSurfaceClassName, 'w-[min(520px,calc(100vw-32px))]')}
				data-testid="bridge-review-facet-popover"
				sideOffset={6}
			>
				<header className="px-2 pb-2 pt-1" data-testid="bridge-review-facet-popover-header">
					<p className="text-[13px] font-medium text-[var(--bridge-text-primary)]">
						Filter review files
					</p>
					<p className="mt-0.5 text-[11px] text-[var(--bridge-text-muted)]">
						Refine the file set without changing the review mode
					</p>
				</header>
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				<div className="grid gap-2 sm:grid-cols-2" data-testid="bridge-review-facet-columns">
					<BridgeReviewFacetGroup
						activeValue={props.gitStatusFilter}
						defaultValue="all"
						label="Git status"
						onChange={props.onGitStatusFilterChange}
						options={props.gitStatusOptions}
					/>
					<BridgeReviewFacetGroup
						activeValue={props.fileClassFilter}
						defaultValue="all"
						label="File type"
						onChange={props.onFileClassFilterChange}
						options={props.fileClassOptions}
					/>
				</div>
				<DropdownMenuSeparator className="my-1 bg-[var(--bridge-border-subtle)]" />
				<DropdownMenuItem
					className={bridgeViewerFilterClearClassName}
					data-testid="bridge-review-facet-clear"
					disabled={!hasActiveFacet}
					onClick={() => {
						props.onGitStatusFilterChange('all');
						props.onFileClassFilterChange('all');
					}}
				>
					<span className="flex size-5 shrink-0 items-center justify-center rounded-[6px] bg-[var(--bridge-surface-muted-bg)] text-[var(--bridge-text-secondary)]">
						<XIcon aria-hidden="true" className="size-3.5" />
					</span>
					<span>Clear filters</span>
				</DropdownMenuItem>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function BridgeReviewFacetGroup<TValue extends string>(props: {
	readonly activeValue: TValue;
	readonly defaultValue: TValue;
	readonly label: string;
	readonly options: readonly BridgeReviewFacetMenuOption<TValue>[];
	readonly onChange: (value: TValue) => void;
}): ReactElement {
	const visibleOptions = props.options.filter(
		(option: BridgeReviewFacetMenuOption<TValue>): boolean => option.value !== props.defaultValue,
	);

	return (
		<section aria-label={props.label} data-testid="bridge-review-facet-group">
			<p className="px-2 pb-1 pt-1 text-[11px] font-medium uppercase tracking-normal text-[var(--bridge-text-muted)]">
				{props.label}
			</p>
			<div className="space-y-0.5">
				{visibleOptions.map(
					(option: BridgeReviewFacetMenuOption<TValue>): ReactElement => (
						<DropdownMenuCheckboxItem
							checked={option.value === props.activeValue}
							className={cn(
								bridgeViewerFilterOptionClassName,
								'min-h-10 py-1.5',
								option.value === props.activeValue && 'text-[var(--bridge-text-primary)]',
							)}
							data-testid="bridge-review-facet-option"
							key={option.value}
							onClick={() => props.onChange(option.value)}
						>
							<span
								aria-hidden="true"
								className={cn(
									'flex size-5 shrink-0 items-center justify-center rounded-[6px]',
									'text-[10px] font-semibold leading-none',
									facetBadgeClassName(option.value),
								)}
								data-testid="bridge-review-facet-option-badge"
							>
								{option.icon ?? option.label.slice(0, 1)}
							</span>
							<span className="min-w-0">
								<span className="block truncate" data-testid="bridge-review-facet-option-label">
									{option.label}
								</span>
								<span
									className="block truncate text-[11px] text-[var(--bridge-text-muted)]"
									data-testid="bridge-review-facet-option-description"
								>
									{option.description}
								</span>
							</span>
						</DropdownMenuCheckboxItem>
					),
				)}
			</div>
		</section>
	);
}

export function bridgeReviewFileClassIcon(fileClass: BridgeFileClass | 'all'): ReactNode {
	if (fileClass === 'all') {
		return '*';
	}
	if (fileClass === 'docs') {
		return <FolderIcon aria-hidden="true" className="size-3.5" />;
	}
	return fileClass.slice(0, 1).toUpperCase();
}

function facetBadgeClassName(value: string): string {
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
		default:
			return 'bg-[color-mix(in_oklch,var(--bridge-text-muted)_18%,transparent)] text-[var(--bridge-text-secondary)]';
	}
}
