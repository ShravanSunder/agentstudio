import { afterEach, describe, expect, test } from 'vitest';

import { applyReviewTreeSelectionFromEvent } from './bridge-trees-panel.js';

const originalWindowDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'window');

interface BridgeReviewTreeClickProbeTestWindow {
	__bridgeReviewTreeClickProbe?: {
		captureHandlerInvokedCount?: number;
		captureHandlerResolvedRowItemId?: string;
		selectionCommandIssuedCount?: number;
		selectionCommandAcceptedCount?: number;
		selectionCommandLastResult?: string;
	};
}

afterEach(() => {
	if (originalWindowDescriptor === undefined) {
		// oxlint-disable-next-line no-dynamic-delete -- Restores the non-DOM unit test global.
		delete (globalThis as typeof globalThis & { window?: Window }).window;
		return;
	}
	Object.defineProperty(globalThis, 'window', originalWindowDescriptor);
});

describe('BridgeReviewTreesPanel selection dispatch', () => {
	test('applies a composed post-scroll host click for the rendered row path', async () => {
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
		expect(selectedItemIds).toEqual([]);

		await Promise.resolve();

		expect(selectedItemIds).toEqual(['post-scroll-target-item']);
	});

	test('defers the React selection callback outside the click handler task', async () => {
		const selectedItemIds: string[] = [];
		const selectedTreePaths: string[] = [];
		const renderedRow = new RecordingReviewTreeRowElement('src/async-target.ts');
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
				'src/async-target.ts': 'async-target-item',
			},
			selectClickedTreePath: (path: string): string | null => {
				selectedTreePaths.push(path);
				return path === 'src/async-target.ts' ? 'async-target-item' : null;
			},
		});

		expect(didSelect).toBe(true);
		expect(selectedTreePaths).toEqual(['src/async-target.ts']);
		expect(selectedItemIds).toEqual([]);

		await Promise.resolve();

		expect(selectedItemIds).toEqual(['async-target-item']);
	});

	test('records capture handler and selection command breadcrumbs on the tree click probe', () => {
		const probeWindow: BridgeReviewTreeClickProbeTestWindow = {};
		Object.defineProperty(globalThis, 'window', { configurable: true, value: probeWindow });
		// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
		delete probeWindow.__bridgeReviewTreeClickProbe;
		const renderedRow = new RecordingReviewTreeRowElement('src/probed-target.ts');
		const postScrollHostClick = new Event('click', { bubbles: true, composed: true });
		Object.defineProperty(postScrollHostClick, 'composedPath', {
			value: (): readonly unknown[] => [renderedRow, {}],
		});

		applyReviewTreeSelectionFromEvent({
			event: postScrollHostClick,
			onSelectItem: (): void => {},
			primaryItemIdByTreePath: {
				'src/probed-target.ts': 'probed-target-item',
			},
			selectClickedTreePath: (): string | null => 'probed-target-item',
		});

		// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
		expect(probeWindow.__bridgeReviewTreeClickProbe).toMatchObject({
			captureHandlerInvokedCount: 1,
			captureHandlerResolvedRowItemId: 'probed-target-item',
			selectionCommandIssuedCount: 1,
			selectionCommandAcceptedCount: 1,
			selectionCommandLastResult: 'accepted',
		});
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
