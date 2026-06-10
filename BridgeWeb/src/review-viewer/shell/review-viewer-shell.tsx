import type { ReactElement } from 'react';

import { orderedReviewItems } from '../../foundation/review-package/bridge-review-package-adapter.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';

export interface ReviewViewerShellProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly onSelectItem: (itemId: string) => void;
}

export function ReviewViewerShell(props: ReviewViewerShellProps): ReactElement {
	const items = orderedReviewItems(props.reviewPackage);

	return (
		<main data-testid="review-viewer-shell">
			<nav aria-label="Changed files">
				{items.map((item) => (
					<button
						aria-current={props.selectedItemId === item.itemId ? 'true' : undefined}
						key={item.itemId}
						onClick={() => props.onSelectItem(item.itemId)}
						type="button"
					>
						{item.headPath ?? item.basePath ?? item.itemId}
					</button>
				))}
			</nav>
		</main>
	);
}
