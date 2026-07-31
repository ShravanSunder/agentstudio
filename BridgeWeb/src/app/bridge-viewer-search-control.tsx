import { SearchIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { BridgeViewerButton, BridgeViewerIcon } from './bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from './bridge-viewer-chrome.js';

export interface BridgeViewerSearchControlProps {
	readonly isActive: boolean;
	readonly onToggleSearch: () => void;
	readonly searchToggleTestId: string;
	readonly testId: string;
}

export function BridgeViewerSearchControl(props: BridgeViewerSearchControlProps): ReactElement {
	return (
		<div className="relative flex min-w-0 items-center" data-testid={props.testId}>
			<BridgeViewerButton
				ariaLabel="Search files"
				ariaPressed={props.isActive}
				className={bridgeViewerChromeIconButtonClassName}
				onClick={props.onToggleSearch}
				testId={props.searchToggleTestId}
				title={props.isActive ? 'Close file search' : 'Search files'}
			>
				<BridgeViewerIcon>
					<SearchIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeViewerIcon>
			</BridgeViewerButton>
		</div>
	);
}
