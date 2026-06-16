import type { ReactElement, ReactNode } from 'react';
import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import {
	loadSelectedReviewItemContent,
	loadSelectedReviewItemContentResources,
	ReviewViewerShell,
} from './review-viewer-shell.js';

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
			projection: projectionForPackage(reviewPackage),
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
	});

	test('renders projection and tree refinement controls for fast review view switching', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const element = ReviewViewerShell({
			reviewPackage,
			projection: projectionForPackage(reviewPackage),
			selectedItemId: 'item-source',
			onSelectItem: () => undefined,
			selectedContentText: null,
		});

		const text = collectText(element);
		expect(text).toContain('All');
		expect(text).toContain('Changed');
		expect(text).toContain('Guided');
		expect(text).toContain('Change set');
		expect(text).toContain('Docs/plans');
		expect(text).toContain('Tests');
		expect(text).toContain('Source');
		expect(text).toContain('Search files');
		expect(text).toContain('Git status');
		expect(text).toContain('File class');
		expect(text).toContain('Collation:');
	});

	test('uses the dark right-sidebar review layout', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const element = requireTestElement(
			ReviewViewerShell({
				reviewPackage,
				projection: projectionForPackage(reviewPackage),
				selectedItemId: 'item-source',
				onSelectItem: () => undefined,
				selectedContentText: null,
			}),
		);

		expect(element.props['data-sidebar-position']).toBe('right');
		expect(classNameForElement(element)).toContain('bg-[var(--bridge-app-bg)]');

		const canvas = findElementByTestId(element, 'bridge-review-canvas');
		const sidebar = findElementByTestId(element, 'bridge-review-sidebar');

		expect(canvas?.type).toBe('section');
		expect(classNameForElement(canvas)).toContain('bg-[var(--bridge-canvas-bg)]');
		expect(sidebar?.type).toBe('aside');
		expect(classNameForElement(sidebar)).toContain('order-last');
		expect(classNameForElement(sidebar)).toContain('border-l');
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

	test('loads selected diff content through base and head handles', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItem = reviewPackage.itemsById['item-source'];
		const baseHandle = selectedItem?.contentRoles.base;
		const headHandle = selectedItem?.contentRoles.head;
		if (baseHandle === undefined || baseHandle === null) {
			throw new Error('expected base content handle');
		}
		if (headHandle === undefined || headHandle === null) {
			throw new Error('expected head content handle');
		}
		const requestedUrls: string[] = [];

		const loaded = await loadSelectedReviewItemContentResources({
			reviewPackage,
			selectedItemId: 'item-source',
			fetchContent: async (url: string): Promise<Response> => {
				requestedUrls.push(url);
				return new Response(url === baseHandle.resourceUrl ? 'base text' : 'head text');
			},
		});

		expect(requestedUrls).toEqual([baseHandle.resourceUrl, headHandle.resourceUrl]);
		expect(loaded).toMatchObject({
			base: { text: 'base text' },
			head: { text: 'head text' },
		});
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
			projection: projectionForPackage(reviewPackage),
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

interface TestElementProps {
	readonly children?: ReactNode;
	readonly className?: string;
	readonly 'data-sidebar-position'?: string;
	readonly 'data-testid'?: string;
}

function isReactElement(node: ReactNode): node is ReactElement<TestElementProps> {
	return typeof node === 'object' && node !== null && 'props' in node;
}

function requireTestElement(node: ReactNode): ReactElement<TestElementProps> {
	if (!isReactElement(node)) {
		throw new Error('expected React element');
	}
	return node;
}

function findElementByTestId(
	node: ReactNode,
	testId: string,
): ReactElement<TestElementProps> | null {
	if (Array.isArray(node)) {
		for (const child of node) {
			const match = findElementByTestId(child, testId);
			if (match !== null) {
				return match;
			}
		}
		return null;
	}
	if (!isReactElement(node)) {
		return null;
	}
	if (node.props['data-testid'] === testId) {
		return node;
	}
	return findElementByTestId(node.props.children, testId);
}

function classNameForElement(element: ReactElement<TestElementProps> | null): string {
	return element?.props.className ?? '';
}

function projectionForPackage(
	reviewPackage: BridgeReviewPackage,
): ReturnType<typeof buildBridgeReviewProjection> {
	return buildBridgeReviewProjection({
		reviewPackage,
		request: { base: { kind: 'allFiles' }, refinements: [] },
	});
}
