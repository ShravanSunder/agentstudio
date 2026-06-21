// @vitest-environment jsdom

import { describe, expect, test } from 'vitest';

import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { syncBridgeCodeViewLoadingBody } from './bridge-code-view-loading-body.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';

describe('Bridge CodeView loading body', () => {
	test('renders shadcn skeleton rows inside a loading CodeView item container', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		if (item === undefined) {
			throw new Error('expected added-file fixture item');
		}
		const loadingItem = materializeBridgeCodeViewLoadingItem(item);
		const containerElement = document.createElement('div');

		syncBridgeCodeViewLoadingBody({
			containerElement,
			item: loadingItem,
			phase: 'mount',
		});

		const loadingBody = containerElement.querySelector(
			'[data-testid="bridge-code-view-loading-body"]',
		);
		expect(containerElement.getAttribute('data-bridge-code-view-loading-item')).toBe('true');
		expect(loadingBody).not.toBeNull();
		expect(loadingBody?.querySelectorAll('[data-slot="skeleton"]')).toHaveLength(3);
	});

	test('removes loading skeleton rows when the CodeView item unmounts', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const item = reviewPackage.itemsById['hidden-binary'];
		if (item === undefined) {
			throw new Error('expected added-file fixture item');
		}
		const loadingItem = materializeBridgeCodeViewLoadingItem(item);
		const containerElement = document.createElement('div');
		syncBridgeCodeViewLoadingBody({
			containerElement,
			item: loadingItem,
			phase: 'mount',
		});

		syncBridgeCodeViewLoadingBody({
			containerElement,
			item: loadingItem,
			phase: 'unmount',
		});

		expect(containerElement.getAttribute('data-bridge-code-view-loading-item')).toBeNull();
		expect(
			containerElement.querySelector('[data-testid="bridge-code-view-loading-body"]'),
		).toBeNull();
	});
});
