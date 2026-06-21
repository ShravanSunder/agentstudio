import type { CodeViewLineSelection, CodeViewScrollTarget } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { BridgeCodeViewController } from './bridge-code-view-controller.js';
import {
	createBridgeCodeViewInitialItems,
	type BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';

describe('BridgeCodeViewController', () => {
	test('updates an existing item and scrolls to it without replacing the item registry', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		const model = new RecordingCodeViewModel([firstItem]);
		const controller = new BridgeCodeViewController({ model });
		const updatedItem: BridgeCodeViewItem = {
			...firstItem,
			version: 1,
			bridgeMetadata: {
				...firstItem.bridgeMetadata,
				contentState: 'hydrated',
			},
		};

		const result = controller.applyItemUpdate(updatedItem, { scrollIntoView: true });

		expect(result).toBe('updated');
		expect(model.addedItems).toEqual([]);
		expect(model.updatedItems).toEqual([updatedItem]);
		expect(model.scrollTargets).toEqual([
			{ type: 'item', id: firstItem.id, align: 'start', behavior: 'instant' },
		]);
	});

	test('adds a missing item before scrolling to it', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		const model = new RecordingCodeViewModel([]);
		const controller = new BridgeCodeViewController({ model });

		const result = controller.applyItemUpdate(firstItem, { scrollIntoView: true });

		expect(result).toBe('added');
		expect(model.addedItems).toEqual([firstItem]);
		expect(model.updatedItems).toEqual([]);
		expect(model.scrollTargets).toEqual([
			{ type: 'item', id: firstItem.id, align: 'start', behavior: 'instant' },
		]);
	});

	test('does not ask CodeView to scroll to an item missing from the current model', () => {
		const model = new RecordingCodeViewModel([]);
		const controller = new BridgeCodeViewController({ model });

		controller.scrollToItem('filtered-out-item');

		expect(model.scrollTargets).toEqual([]);
	});

	test('treats an unchanged existing item update as a no-op without adding a duplicate', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		const model = new RecordingCodeViewModel([firstItem], {
			updateReturnValue: false,
		});
		const controller = new BridgeCodeViewController({ model });

		const result = controller.applyItemUpdate(firstItem, { scrollIntoView: true });

		expect(result).toBe('unchanged');
		expect(model.addedItems).toEqual([]);
		expect(model.updatedItems).toEqual([firstItem]);
		expect(model.scrollTargets).toEqual([
			{ type: 'item', id: firstItem.id, align: 'start', behavior: 'instant' },
		]);
	});
});

interface RecordingCodeViewModelOptions {
	readonly updateReturnValue?: boolean;
}

class RecordingCodeViewModel {
	readonly addedItems: BridgeCodeViewItem[] = [];
	readonly updatedItems: BridgeCodeViewItem[] = [];
	readonly scrollTargets: CodeViewScrollTarget[] = [];
	readonly selectedLineWrites: (CodeViewLineSelection | null)[] = [];
	readonly renamedItems: [string, string][] = [];
	readonly #itemsById = new Map<string, BridgeCodeViewItem>();
	readonly #updateReturnValue: boolean;

	constructor(items: readonly BridgeCodeViewItem[], options: RecordingCodeViewModelOptions = {}) {
		this.#updateReturnValue = options.updateReturnValue ?? true;
		for (const item of items) {
			this.#itemsById.set(item.id, item);
		}
	}

	addItems(items: readonly BridgeCodeViewItem[]): void {
		for (const item of items) {
			this.addedItems.push(item);
			this.#itemsById.set(item.id, item);
		}
	}

	getItem(id: string): BridgeCodeViewItem | undefined {
		return this.#itemsById.get(id);
	}

	updateItem(item: BridgeCodeViewItem): boolean {
		if (!this.#itemsById.has(item.id)) {
			return false;
		}
		this.updatedItems.push(item);
		this.#itemsById.set(item.id, item);
		return this.#updateReturnValue;
	}

	updateItemId(oldId: string, newId: string): boolean {
		const item = this.#itemsById.get(oldId);
		if (item === undefined) {
			return false;
		}
		this.renamedItems.push([oldId, newId]);
		this.#itemsById.delete(oldId);
		this.#itemsById.set(newId, { ...item, id: newId });
		return true;
	}

	scrollTo(target: CodeViewScrollTarget): void {
		this.scrollTargets.push(target);
	}

	setSelectedLines(selection: CodeViewLineSelection | null): void {
		this.selectedLineWrites.push(selection);
	}
}
