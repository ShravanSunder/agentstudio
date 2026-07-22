import { act } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode mounts the production Review tree.
import '../../app/bridge-app.css';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { BridgeReviewTreesPanel } from './bridge-trees-panel.js';

describe('BridgeReviewTreesPanel hover lifecycle', () => {
	test('clears Review hover exactly once when the tree unmounts', async () => {
		// Arrange
		const hoveredItemIds: Array<string | null> = [];
		const reviewPackage = makeBridgeReviewPackage();
		const rendered = await render(
			<BridgeReviewTreesPanel
				isActive={true}
				onHoveredItemIdChange={(itemId): void => {
					hoveredItemIds.push(itemId);
				}}
				onSelectItem={(): void => {}}
				presentationPositionKey="hover-lifecycle"
				projection={buildBridgeReviewProjection({
					reviewPackage,
					request: { facets: [], mode: { kind: 'normalReview' } },
				})}
				reviewPackage={reviewPackage}
				reviewTreeRows={[]}
				searchMode={{ kind: 'text' }}
				searchText=""
				selectedItemId={null}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.unmount();
			await Promise.resolve();
		});

		// Assert
		expect(hoveredItemIds).toEqual([null]);
	});
});
