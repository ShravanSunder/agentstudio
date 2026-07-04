import { describe, expect, test } from 'vitest';

import { applyReviewTreeSelectionFromEvent } from './bridge-trees-panel.js';

describe('BridgeReviewTreesPanel selection dispatch', () => {
	test('applies a composed post-scroll host click for the rendered row path', () => {
		const selectedItemIds: string[] = [];
		const selectedTreePaths: string[] = [];
		const renderedRow = new RecordingReviewTreeRowElement('src/post-scroll-target.ts');
		const postScrollHostClick = new Event('click', { bubbles: true, composed: true });
		Object.defineProperty(postScrollHostClick, 'composedPath', {
			value: (): readonly unknown[] => [renderedRow, {}],
		});

		const didSelect = applyReviewTreeSelectionFromEvent({
			event: postScrollHostClick,
			onSelectItem: (itemId: string): void => {
				selectedItemIds.push(itemId);
			},
			primaryItemIdByTreePath: {
				'src/post-scroll-target.ts': 'post-scroll-target-item',
			},
			selectClickedTreePath: (path: string): string | null => {
				selectedTreePaths.push(path);
				return path === 'src/post-scroll-target.ts' ? 'post-scroll-target-item' : null;
			},
		});

		expect(didSelect).toBe(true);
		expect(selectedTreePaths).toEqual(['src/post-scroll-target.ts']);
		expect(selectedItemIds).toEqual(['post-scroll-target-item']);
	});
});

class RecordingReviewTreeRowElement {
	constructor(private readonly path: string) {}

	getAttribute(name: string): string | null {
		if (name === 'data-item-type') {
			return 'file';
		}
		return name === 'data-item-path' ? this.path : null;
	}
}
