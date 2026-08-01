import type { ReactElement } from 'react';

import {
	BridgeViewerFacetGroup,
	BridgeViewerFacetMenu,
	type BridgeViewerFacetMenuOption,
} from '../../app/bridge-viewer-filter-menu.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
} from '../../foundation/review-package/bridge-review-package.js';

export interface BridgeReviewFacetMenuProps {
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
	readonly gitStatusOptions: readonly BridgeViewerFacetMenuOption<BridgeFileChangeKind | 'all'>[];
	readonly fileClassOptions: readonly BridgeViewerFacetMenuOption<BridgeFileClass | 'all'>[];
	readonly onGitStatusFilterChange: (status: BridgeFileChangeKind | 'all') => void;
	readonly onFileClassFilterChange: (fileClass: BridgeFileClass | 'all') => void;
	readonly onOpenChange: (open: boolean) => void;
	readonly open: boolean;
}

export function BridgeReviewFacetMenu(props: BridgeReviewFacetMenuProps): ReactElement {
	const hasActiveGitFilter = props.gitStatusFilter !== 'all';
	const hasActiveFileClassFilter = props.fileClassFilter !== 'all';
	const hasActiveFacet = hasActiveGitFilter || hasActiveFileClassFilter;

	return (
		<BridgeViewerFacetMenu
			clearDisabled={!hasActiveFacet}
			clearLabel="Clear filters"
			clearTestId="bridge-review-facet-clear"
			contentClassName="w-[min(520px,calc(100vw-32px))]"
			contentTestId="bridge-review-facet-popover"
			description="Refine the file set without changing the review mode"
			hasActiveFilter={hasActiveFacet}
			headerTestId="bridge-review-facet-popover-header"
			label="Filter review files"
			onClear={() => {
				props.onGitStatusFilterChange('all');
				props.onFileClassFilterChange('all');
			}}
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
					onChange={props.onGitStatusFilterChange}
					optionBadgeTestId="bridge-review-facet-option-badge"
					optionLabelTestId="bridge-review-facet-option-label"
					optionTestId="bridge-review-facet-option"
					options={props.gitStatusOptions}
					testId="bridge-review-facet-group"
				/>
				<BridgeViewerFacetGroup
					activeValue={props.fileClassFilter}
					defaultValue="all"
					label="File type"
					onChange={props.onFileClassFilterChange}
					optionBadgeTestId="bridge-review-facet-option-badge"
					optionLabelTestId="bridge-review-facet-option-label"
					optionTestId="bridge-review-facet-option"
					options={props.fileClassOptions}
					testId="bridge-review-facet-group"
				/>
			</div>
		</BridgeViewerFacetMenu>
	);
}
