import { RegexIcon, SearchIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import {
	bridgeViewerChromeIconButtonClassName,
	bridgeViewerChromeLucideIconClassName,
} from '../../app/bridge-viewer-chrome.js';
import type { BridgeReviewSearchMode } from '../models/review-projection-models.js';
import { BridgeReviewButton, BridgeReviewIcon } from './bridge-review-button.js';

export interface BridgeReviewSearchControlProps {
	readonly isActive: boolean;
	readonly onOpenSearch: () => void;
	readonly searchMode?: BridgeReviewSearchMode;
	readonly onSearchModeChange?: (mode: BridgeReviewSearchMode) => void;
}

export function BridgeReviewSearchControl(props: BridgeReviewSearchControlProps): ReactElement {
	const searchMode = props.searchMode ?? { kind: 'text' };
	const isRegexMode = searchMode.kind === 'regex';

	return (
		<div
			className="relative flex min-w-0 items-center gap-1"
			data-testid="bridge-review-search-control"
		>
			<BridgeReviewButton
				ariaLabel="Search files"
				ariaPressed={props.isActive}
				className={bridgeViewerChromeIconButtonClassName}
				onClick={props.onOpenSearch}
				testId="bridge-review-search-toggle"
				title="Search files"
			>
				<BridgeReviewIcon>
					<SearchIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeReviewIcon>
			</BridgeReviewButton>
			<BridgeReviewButton
				ariaLabel={isRegexMode ? 'Use text search' : 'Use regex search'}
				ariaPressed={isRegexMode}
				className={bridgeViewerChromeIconButtonClassName}
				onClick={(): void => {
					props.onSearchModeChange?.(isRegexMode ? { kind: 'text' } : { kind: 'regex' });
				}}
				testId="bridge-review-regex-toggle"
				title={isRegexMode ? 'Use text search' : 'Use regex search'}
			>
				<BridgeReviewIcon>
					<RegexIcon aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
				</BridgeReviewIcon>
			</BridgeReviewButton>
		</div>
	);
}
