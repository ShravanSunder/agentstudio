import { describe, expect, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	createBridgeCodeViewInitialItems,
	materializeBridgeCodeViewLoadingItem,
} from './bridge-code-view-materialization.js';

describe('Bridge CodeView materialization cutover', () => {
	test('preserves placeholder height while selected content loads through worker-prepared items', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const item = reviewPackage.itemsById['source-high'];
		if (item === undefined) {
			throw new Error('expected source fixture item');
		}
		const placeholder = createBridgeCodeViewInitialItems({ reviewPackage, projection }).find(
			(candidate): boolean => candidate.id === item.itemId,
		);
		if (placeholder === undefined) {
			throw new Error('expected source fixture placeholder');
		}

		const loadingItem = materializeBridgeCodeViewLoadingItem(item);

		expect(loadingItem.bridgeMetadata.lineCount).toBe(placeholder.bridgeMetadata.lineCount);
		if (loadingItem.type === 'file' && placeholder.type === 'file') {
			expect(countContentLines(loadingItem.file.contents)).toBe(
				countContentLines(placeholder.file.contents),
			);
		}
	});
});

function countContentLines(contents: string): number {
	return contents === '' ? 0 : contents.split('\n').length - 1;
}
