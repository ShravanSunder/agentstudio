import type { ReactElement } from 'react';

import { bridgeViewerFileCategoryOptions } from '../app/bridge-viewer-file-class-options.js';
import { BridgeViewerFacetGroup, BridgeViewerFacetMenu } from '../app/bridge-viewer-filter-menu.js';
import type { BridgeFileViewerFilterMode } from './bridge-file-viewer-contracts.js';

export interface BridgeFileViewerFacetMenuProps {
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly onFilterModeChange: (filterMode: BridgeFileViewerFilterMode) => void;
	readonly onOpenChange: (open: boolean) => void;
	readonly open: boolean;
}

export function BridgeFileViewerFacetMenu(props: BridgeFileViewerFacetMenuProps): ReactElement {
	const hasActiveFilter = props.filterMode !== 'all';

	return (
		<BridgeViewerFacetMenu
			clearDisabled={!hasActiveFilter}
			clearLabel="Clear filter"
			clearTestId="worktree-file-filter-menu-clear"
			contentClassName="w-[min(520px,calc(100vw-32px))]"
			contentTestId="worktree-file-filter-menu-popover"
			description="Refine the file set without changing the Files mode"
			hasActiveFilter={hasActiveFilter}
			headerTestId="worktree-file-filter-menu-popover-header"
			label="Filter files"
			onClear={() => props.onFilterModeChange('all')}
			onOpenChange={props.onOpenChange}
			open={props.open}
			selectedLabel="File filters"
			testId="worktree-file-filter-menu"
			title="Filter files"
			triggerActiveIndicatorTestId="worktree-file-filter-menu-active-indicator"
			triggerGlyphTestId="worktree-file-filter-menu-trigger-glyph"
		>
			<BridgeViewerFacetGroup
				activeValue={props.filterMode}
				defaultValue="all"
				label="File category"
				onChange={props.onFilterModeChange}
				optionBadgeTestId="worktree-file-filter-menu-option-badge"
				optionLabelTestId="worktree-file-filter-menu-option-label"
				optionTestId="worktree-file-filter-menu-option"
				options={bridgeViewerFileCategoryOptions}
				testId="worktree-file-filter-menu-group"
			/>
		</BridgeViewerFacetMenu>
	);
}
