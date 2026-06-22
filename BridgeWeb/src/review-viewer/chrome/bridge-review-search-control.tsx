import { RegexIcon, SearchIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { cn } from '../../app/class-name.js';
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
				className={cn(
					'h-7 w-7 rounded-md border-transparent bg-transparent px-0',
					props.isActive && 'bg-[var(--bridge-accent-soft)] text-[var(--bridge-text-primary)]',
				)}
				onClick={props.onOpenSearch}
				testId="bridge-review-search-toggle"
				title="Search files"
			>
				<BridgeReviewIcon>
					<SearchIcon aria-hidden="true" className="size-4" />
				</BridgeReviewIcon>
			</BridgeReviewButton>
			<BridgeReviewButton
				ariaLabel={isRegexMode ? 'Use text search' : 'Use regex search'}
				ariaPressed={isRegexMode}
				className={cn(
					'h-7 w-7 rounded-md border-transparent bg-transparent px-0',
					isRegexMode && 'bg-[var(--bridge-accent-soft)] text-[var(--bridge-text-primary)]',
				)}
				onClick={(): void => {
					props.onSearchModeChange?.(isRegexMode ? { kind: 'text' } : { kind: 'regex' });
				}}
				testId="bridge-review-regex-toggle"
				title={isRegexMode ? 'Use text search' : 'Use regex search'}
			>
				<BridgeReviewIcon>
					<RegexIcon aria-hidden="true" className="size-4" />
				</BridgeReviewIcon>
			</BridgeReviewButton>
		</div>
	);
}
