import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { ReviewViewerShell } from './review-viewer-shell.js';

describe('review viewer shell', () => {
	test('creates a React element from a review package', () => {
		const element = ReviewViewerShell({
			reviewPackage: makeBridgeReviewPackage(),
			selectedItemId: 'item-source',
			onSelectItem: () => undefined,
		});

		expect(element.type).toBe('main');
		expect(element).toMatchObject({
			props: {
				'data-testid': 'review-viewer-shell',
			},
		});
	});
});
