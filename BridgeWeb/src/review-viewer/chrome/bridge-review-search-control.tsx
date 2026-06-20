import { SearchIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { cn } from '../../app/class-name.js';
import { BridgeReviewButton, BridgeReviewIcon } from './bridge-review-button.js';

export interface BridgeReviewSearchControlProps {
	readonly isActive: boolean;
	readonly onOpenSearch: () => void;
}

export function BridgeReviewSearchControl(props: BridgeReviewSearchControlProps): ReactElement {
	return (
		<div className="relative flex min-w-0 items-center" data-testid="bridge-review-search-control">
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
		</div>
	);
}
