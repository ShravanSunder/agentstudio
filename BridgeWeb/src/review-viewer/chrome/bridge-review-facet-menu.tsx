import { BinaryIcon, FileWarningIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import type { BridgeFileTreeFilterCandidate } from '../../app/bridge-app-control.js';
import {
	bridgeViewerFileCategoryOptions,
	type BridgeViewerFileCategory,
} from '../../app/bridge-viewer-file-class-options.js';
import {
	BridgeViewerFacetGroup,
	BridgeViewerFacetMenu,
	BridgeViewerFacetToggleRow,
	type BridgeViewerFacetMenuOption,
} from '../../app/bridge-viewer-filter-menu.js';
import { DropdownMenuGroup } from '../../components/ui/dropdown-menu.js';
import type { BridgeFileChangeKind } from '../../foundation/review-package/bridge-review-package.js';

type BridgeReviewFilterCandidate = Extract<
	BridgeFileTreeFilterCandidate,
	{ readonly surface: 'review' }
>;

export interface BridgeReviewFacetMenuProps {
	readonly categoryFilter: BridgeViewerFileCategory | 'all';
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly gitStatusOptions: readonly BridgeViewerFacetMenuOption<BridgeFileChangeKind | 'all'>[];
	readonly onFilterChange: (filter: BridgeReviewFilterCandidate) => void;
	readonly onOpenChange: (open: boolean) => void;
	readonly open: boolean;
	readonly showBinary: boolean;
	readonly showLarge: boolean;
}

export function BridgeReviewFacetMenu(props: BridgeReviewFacetMenuProps): ReactElement {
	const hasActiveGitFilter = props.gitStatusFilter !== 'all';
	const hasActiveCategoryFilter = props.categoryFilter !== 'all';
	const hasActiveFacet =
		hasActiveGitFilter || hasActiveCategoryFilter || props.showBinary || props.showLarge;

	return (
		<BridgeViewerFacetMenu
			columns
			clearDisabled={!hasActiveFacet}
			clearLabel="Clear filters"
			clearTestId="bridge-review-facet-clear"
			contentTestId="bridge-review-facet-popover"
			description="Refine the file set without changing the review mode"
			hasActiveFilter={hasActiveFacet}
			headerTestId="bridge-review-facet-popover-header"
			label="Filter review files"
			onClear={() =>
				props.onFilterChange({
					categoryFilter: 'all',
					gitStatusFilter: 'all',
					showBinary: false,
					showLarge: false,
					surface: 'review',
				})
			}
			onOpenChange={props.onOpenChange}
			open={props.open}
			selectedLabel="Review filters"
			testId="bridge-review-facet-menu-control"
			title="Filter review files"
			triggerActiveIndicatorTestId="bridge-review-facet-active-indicator"
			triggerGlyphTestId="bridge-review-facet-trigger-glyph"
		>
			<div className="grid gap-2 sm:grid-cols-2" data-testid="bridge-review-facet-columns">
				<BridgeViewerFacetGroup
					activeValue={props.gitStatusFilter}
					defaultValue="all"
					label="Git status"
					onChange={(gitStatusFilter) =>
						props.onFilterChange({
							categoryFilter: props.categoryFilter,
							gitStatusFilter,
							showBinary: props.showBinary,
							showLarge: props.showLarge,
							surface: 'review',
						})
					}
					optionBadgeTestId="bridge-review-facet-option-badge"
					optionLabelTestId="bridge-review-facet-option-label"
					optionTestId="bridge-review-facet-option"
					options={props.gitStatusOptions}
					testId="bridge-review-facet-group"
				/>
				<BridgeViewerFacetGroup
					activeValue={props.categoryFilter}
					defaultValue="all"
					label="File category"
					onChange={(categoryFilter) =>
						props.onFilterChange({
							categoryFilter,
							gitStatusFilter: props.gitStatusFilter,
							showBinary: props.showBinary,
							showLarge: props.showLarge,
							surface: 'review',
						})
					}
					optionBadgeTestId="bridge-review-facet-option-badge"
					optionLabelTestId="bridge-review-facet-option-label"
					optionTestId="bridge-review-facet-option"
					options={bridgeViewerFileCategoryOptions}
					testId="bridge-review-facet-group"
				/>
				<DropdownMenuGroup
					aria-label="Visibility"
					className="sm:col-span-2"
					data-testid="bridge-review-facet-visibility-group"
				>
					<div className="grid gap-0.5">
						<BridgeViewerFacetToggleRow
							checked={props.showBinary}
							description="Include binary files"
							label="Include binary files"
							icon={<BinaryIcon aria-hidden="true" />}
							onCheckedChange={(showBinary) =>
								props.onFilterChange({
									categoryFilter: props.categoryFilter,
									gitStatusFilter: props.gitStatusFilter,
									showBinary,
									showLarge: props.showLarge,
									surface: 'review',
								})
							}
							testId="bridge-review-facet-show-binary"
						/>
						<BridgeViewerFacetToggleRow
							checked={props.showLarge}
							description="Include files of 1 MB or larger"
							label="Include large files"
							icon={<FileWarningIcon aria-hidden="true" />}
							onCheckedChange={(showLarge) =>
								props.onFilterChange({
									categoryFilter: props.categoryFilter,
									gitStatusFilter: props.gitStatusFilter,
									showBinary: props.showBinary,
									showLarge,
									surface: 'review',
								})
							}
							testId="bridge-review-facet-show-large"
						/>
					</div>
				</DropdownMenuGroup>
			</div>
		</BridgeViewerFacetMenu>
	);
}
