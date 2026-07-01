import { RegexIcon, SearchIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { BridgeViewerButton, BridgeViewerIcon } from './bridge-viewer-button.js';
import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from './bridge-viewer-chrome.js';

export type BridgeViewerSearchMode = { readonly kind: 'regex' | 'text' };

export interface BridgeViewerSearchControlProps {
	readonly isActive: boolean;
	readonly onOpenSearch: () => void;
	readonly searchMode?: BridgeViewerSearchMode;
	readonly onSearchModeChange?: (mode: BridgeViewerSearchMode) => void;
}

export function BridgeViewerSearchControl(props: BridgeViewerSearchControlProps): ReactElement {
	const searchMode = props.searchMode ?? { kind: 'text' };
	const isRegexMode = searchMode.kind === 'regex';

	return (
		<div
			className="relative flex min-w-0 items-center gap-1"
			data-testid="bridge-review-search-control"
		>
			<BridgeViewerButton
				ariaLabel="Search files"
				ariaPressed={props.isActive}
				className={bridgeViewerChromeIconButtonClassName}
				onClick={props.onOpenSearch}
				testId="bridge-review-search-toggle"
				title="Search files"
			>
				<BridgeViewerIcon>
					<SearchIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeViewerIcon>
			</BridgeViewerButton>
			<BridgeViewerButton
				ariaLabel={isRegexMode ? 'Use text search' : 'Use regex search'}
				ariaPressed={isRegexMode}
				className={bridgeViewerChromeIconButtonClassName}
				onClick={(): void => {
					props.onSearchModeChange?.(isRegexMode ? { kind: 'text' } : { kind: 'regex' });
				}}
				testId="bridge-review-regex-toggle"
				title={isRegexMode ? 'Use text search' : 'Use regex search'}
			>
				<BridgeViewerIcon>
					<RegexIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeViewerIcon>
			</BridgeViewerButton>
		</div>
	);
}
