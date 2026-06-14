import type { ReactElement, ReactNode } from 'react';
import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { loadSelectedReviewItemContent, ReviewViewerShell } from './review-viewer-shell.js';

describe('review viewer shell', () => {
	test('renders review package summary endpoints filters and visible item list', () => {
		const basePackage = makeBridgeReviewPackage();
		const reviewPackage = {
			...basePackage,
			query: {
				...basePackage.query,
				pathScope: ['Sources/App/**'],
			},
			baseEndpoint: {
				...basePackage.baseEndpoint,
				kind: 'promptCheckpoint' as const,
				label: 'Prompt checkpoint',
			},
			filterState: {
				...basePackage.filterState,
				includedFileClasses: ['source' as const],
				changeKinds: ['modified' as const],
			},
		};
		const element = ReviewViewerShell({
			reviewPackage,
			selectedItemId: 'item-source',
			onSelectItem: () => undefined,
			selectedContentText: 'selected file text',
		});

		expect(element.type).toBe('main');
		expect(element).toMatchObject({
			props: {
				'data-testid': 'review-viewer-shell',
			},
		});
		const text = collectText(element);
		expect(text).toContain('1 file changed');
		expect(text).toContain('Prompt checkpoint');
		expect(text).toContain('Working tree');
		expect(text).toContain('Checkpoint: Prompt checkpoint');
		expect(text).toContain('Folder: Sources/App/**');
		expect(text).toContain('Class: source');
		expect(text).toContain('Change: modified');
		expect(text).toContain('Sources/App/View.swift');
		expect(text).toContain('selected file text');
	});

	test('loads selected item content through the bridge content handle URL', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItem = reviewPackage.itemsById['item-source'];
		const headHandle = selectedItem?.contentRoles.head;
		if (headHandle === undefined || headHandle === null) {
			throw new Error('expected head content handle');
		}

		const loaded = await loadSelectedReviewItemContent({
			reviewPackage,
			selectedItemId: 'item-source',
			fetchContent: async (url: string): Promise<Response> => {
				expect(url).toBe(headHandle.resourceUrl);
				return new Response('loaded head content');
			},
		});

		expect(loaded?.text).toBe('loaded head content');
	});

	test('renders only items matching folder file-class and change-kind filter state', () => {
		const basePackage = makeBridgeReviewPackage();
		const sourceItem = basePackage.itemsById['item-source'];
		if (sourceItem === undefined) {
			throw new Error('expected source item');
		}
		const hiddenDocsItem = {
			...sourceItem,
			itemId: 'item-docs',
			basePath: 'docs/architecture/old.md',
			headPath: 'docs/architecture/old.md',
			changeKind: 'added' as const,
			fileClass: 'docs' as const,
			extension: 'md',
		};
		const reviewPackage = {
			...basePackage,
			orderedItemIds: ['item-source', 'item-docs'],
			itemsById: {
				'item-source': sourceItem,
				'item-docs': hiddenDocsItem,
			},
			query: {
				...basePackage.query,
				pathScope: ['Sources/**'],
			},
			filterState: {
				...basePackage.filterState,
				includedFileClasses: ['source' as const],
				changeKinds: ['modified' as const],
			},
		};

		const element = ReviewViewerShell({
			reviewPackage,
			selectedItemId: 'item-source',
			onSelectItem: () => undefined,
			selectedContentText: null,
		});

		const text = collectText(element);
		expect(text).toContain('Sources/App/View.swift');
		expect(text).not.toContain('docs/architecture/old.md');
		expect(text).toContain('Folder: Sources/**');
		expect(text).toContain('Class: source');
		expect(text).toContain('Change: modified');
	});
});

function collectText(node: ReactNode): string {
	return collectTextFragments(node).join(' ').replaceAll(/\s+/g, ' ').trim();
}

function collectTextFragments(node: ReactNode): readonly string[] {
	if (typeof node === 'string' || typeof node === 'number') {
		return [String(node)];
	}
	if (Array.isArray(node)) {
		return node.flatMap((child: ReactNode): readonly string[] => collectTextFragments(child));
	}
	if (isReactElement(node)) {
		return collectTextFragments(node.props.children);
	}
	return [];
}

function isReactElement(node: ReactNode): node is ReactElement<{ readonly children?: ReactNode }> {
	return typeof node === 'object' && node !== null && 'props' in node;
}
