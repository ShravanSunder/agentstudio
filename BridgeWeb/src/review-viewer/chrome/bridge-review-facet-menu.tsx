import { FolderIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import {
	BridgeViewerFilterTrigger,
	BridgeViewerFilterClearItem,
	BridgeViewerFilterMenuHeader,
	BridgeViewerFilterOptionRow,
	bridgeViewerFilterMenuSurfaceClassName,
} from '../../app/bridge-viewer-filter-menu.js';
import { cn } from '../../app/class-name.js';
import {
	DropdownMenu,
	DropdownMenuContent,
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
				<BridgeViewerFilterMenuHeader
					description="Refine the file set without changing the review mode"
					testId="bridge-review-facet-popover-header"
					title="Filter review files"
				/>
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
				<BridgeViewerFilterClearItem
					disabled={!hasActiveFacet}
					label="Clear filters"
					onClear={() => {
						props.onGitStatusFilterChange('all');
						props.onFileClassFilterChange('all');
					}}
					testId="bridge-review-facet-clear"
				/>
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
						<BridgeViewerFilterOptionRow
							checked={option.value === props.activeValue}
							icon={option.icon ?? option.label.slice(0, 1)}
							key={option.value}
							label={option.label}
							onSelect={() => props.onChange(option.value)}
							optionBadgeTestId="bridge-review-facet-option-badge"
							optionLabelTestId="bridge-review-facet-option-label"
							optionTestId="bridge-review-facet-option"
							value={option.value}
						/>
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
