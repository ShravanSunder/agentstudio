import type { ReactElement, ReactNode } from 'react';
import { describe, expect, test } from 'vitest';

import {
	DropdownMenuRadioGroup,
	DropdownMenuRadioItem,
} from '../../components/ui/dropdown-menu.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { BridgeReviewFacetMenu } from '../chrome/bridge-review-facet-menu.js';
import { BridgeCodeViewPanel } from '../code-view/bridge-code-view-panel.js';
import { BridgeMarkdownPreview } from '../markdown/bridge-markdown-preview.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import {
	BridgeReviewCanvasLoadingState,
	BridgeReviewProjectionMenu,
	ReviewViewerShell,
} from './review-viewer-shell.js';

describe('review viewer shell', () => {
	test('renders compact rail summary controls and visible item list', () => {
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
		const shell = requireTestElement(element);
		const text = collectText(element);
		const railStats = findElementByTestId(shell, 'bridge-review-rail-stats');

		expect(findElementByTestId(shell, 'bridge-review-top-header')).toBeNull();
		expect(collectText(railStats)).toContain('Files');
		expect(collectText(railStats)).toContain('1');
		expect(collectText(railStats)).toContain('Additions');
		expect(collectText(railStats)).toContain('Deletions');
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
		expect(findElementByComponent(element, BridgeReviewProjectionMenu)).not.toBeNull();
		expect(findElementByComponent(element, BridgeReviewFacetMenu)).not.toBeNull();
		expect(text).toContain('Search files');
		expect(findElementByTestId(element, 'bridge-review-top-header')).toBeNull();
	});

	test('keeps projection scope in compact rail chrome without a top app bar', () => {
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

		const projectionScope = findElementByTestId(element, 'bridge-review-projection-scope');
		const projectionMenu = findElementByComponent(element, BridgeReviewProjectionMenu);
		const facetMenu = findElementByComponent(element, BridgeReviewFacetMenu);
		const railStats = findElementByTestId(element, 'bridge-review-rail-stats');

		expect(findElementByTestId(element, 'bridge-review-top-header')).toBeNull();
		expect(projectionScope).toBeNull();
		expect(projectionMenu).not.toBeNull();
		expect(facetMenu).not.toBeNull();
		expect(railStats).not.toBeNull();
	});

	test('routes projection menu selection through the Base UI radio group change path', () => {
		const element = requireTestElement(
			BridgeReviewProjectionMenu({
				projectionMode: { kind: 'normalReview' },
				onProjectionModeChange: () => undefined,
			}),
		);

		const radioGroup = findElementByComponent(element, DropdownMenuRadioGroup);
		const radioItems = findElementsByComponent(element, DropdownMenuRadioItem);

		expect(radioGroup?.props.onValueChange).toBeTypeOf('function');
		expect(radioItems).toHaveLength(3);
		expect(radioItems.map((item) => item.props.onClick)).toEqual([undefined, undefined, undefined]);
	});

	test('renders custom review controls without native select widgets', () => {
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

		expect(findElementsByType(element, 'select')).toEqual([]);
		expect(findElementByTestId(element, 'bridge-review-facet-menu')).not.toBeNull();
		expect(findElementByTestId(element, 'bridge-review-search-control-slot')).not.toBeNull();
	});

	test('groups right rail controls as compact sidebar toolbar chrome', () => {
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

		const toolbar = findElementByTestId(element, 'bridge-review-rail-toolbar');
		const leadingGroup = findElementByTestId(element, 'bridge-review-rail-toolbar-leading');
		const trailingGroup = findElementByTestId(element, 'bridge-review-rail-toolbar-trailing');
		const fileTreeButton = findElementByTestId(element, 'bridge-review-rail-files-view');
		const commentsButton = findElementByTestId(element, 'bridge-review-rail-comments-view');
		const leadingControlOrder = directChildControlNames(leadingGroup);
		const trailingControlOrder = directChildControlNames(trailingGroup);

		expect(toolbar?.type).toBe('div');
		expect(classNameForElement(toolbar)).toContain('justify-between');
		expect(classNameForElement(leadingGroup)).toContain('gap-1');
		expect(classNameForElement(trailingGroup)).toContain('gap-1');
		expect(leadingControlOrder).toEqual(['BridgeReviewProjectionMenu']);
		expect(trailingControlOrder).toEqual([
			'bridge-review-facet-menu',
			'bridge-review-search-control-slot',
		]);
		expect(fileTreeButton).toBeNull();
		expect(commentsButton).toBeNull();
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
		expect(classNameForElement(canvas)).toContain('h-full');
		expect(classNameForElement(canvas)).toContain('min-h-0');
		expect(sidebar?.type).toBe('aside');
		expect(classNameForElement(sidebar)).toContain('order-last');
		expect(classNameForElement(sidebar)).toContain('border-l');
	});

	test('keeps CodeView and right rail scrolling owned by separate containers', () => {
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
		const shell = findElementByTestId(element, 'review-viewer-shell');
		const codeScroll = findElementByTestId(element, 'bridge-review-code-scroll');
		const railScroll = findElementByTestId(element, 'bridge-review-rail-scroll');
		const railTreeSlot = findElementByTestId(element, 'bridge-review-rail-tree-slot');

		expect(classNameForElement(shell)).toContain('overflow-hidden');
		expect(codeScroll?.type).toBe('section');
		expect(railScroll?.type).toBe('div');
		expect(railTreeSlot?.type).toBe('nav');
		expect(classNameForElement(codeScroll)).toContain('overflow-hidden');
		expect(classNameForElement(codeScroll)).not.toContain('bridge-scrollbar');
		expect(classNameForElement(railScroll)).toContain('overflow-hidden');
		expect(classNameForElement(codeScroll)).toContain('min-h-0');
		expect(classNameForElement(railScroll)).toContain('min-h-0');
		expect(classNameForElement(railTreeSlot)).toContain('h-full');
		expect(classNameForElement(railTreeSlot)).toContain('min-h-0');
	});

	test('exposes selected identity and content readiness from the shell', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const element = requireTestElement(
			ReviewViewerShell({
				reviewPackage,
				projection: projectionForPackage(reviewPackage),
				selectedItemId: 'item-source',
				onSelectItem: () => undefined,
				selectedContentText: null,
				selectedContentResources: {},
			}),
		);
		const shell = findElementByTestId(element, 'review-viewer-shell');

		expect(shell?.props['data-selected-display-path']).toBe('Sources/App/View.swift');
		expect(shell?.props['data-selected-content-state']).toBe('ready');
	});

	test('renders selected markdown preview in the code canvas when worker output is ready', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const element = requireTestElement(
			ReviewViewerShell({
				reviewPackage,
				projection: projectionForPackage(reviewPackage),
				selectedItemId: 'item-source',
				onSelectItem: () => undefined,
				selectedContentText: null,
				selectedMarkdownPreviewHtml: '<h1>Bridge plan</h1>',
				selectedMarkdownPreviewSourcePath: 'docs/plans/bridge-plan.md',
			}),
		);

		const markdownPreview = findElementByComponent(element, BridgeMarkdownPreview);
		const codeViewPanel = findElementByComponent(element, BridgeCodeViewPanel);

		expect(markdownPreview?.type).toBe(BridgeMarkdownPreview);
		expect(codeViewPanel).toBeNull();
	});

	test('keeps CodeView while markdown worker output is not ready', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const element = requireTestElement(
			ReviewViewerShell({
				reviewPackage,
				projection: projectionForPackage(reviewPackage),
				selectedItemId: 'item-source',
				onSelectItem: () => undefined,
				selectedContentText: null,
				selectedMarkdownPreviewHtml: null,
				selectedMarkdownPreviewSourcePath: null,
			}),
		);

		expect(findElementByComponent(element, BridgeMarkdownPreview)).toBeNull();
		expect(findElementByComponent(element, BridgeCodeViewPanel)).not.toBeNull();
	});

	test('shows a shadcn canvas skeleton while markdown output is rendering', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const element = requireTestElement(
			ReviewViewerShell({
				reviewPackage,
				projection: projectionForPackage(reviewPackage),
				selectedItemId: 'item-source',
				onSelectItem: () => undefined,
				selectedContentText: null,
				selectedCanvasLoadingReason: 'markdownPreview',
				selectedMarkdownPreviewHtml: null,
				selectedMarkdownPreviewSourcePath: null,
			}),
		);

		const loadingState = findElementByComponent(element, BridgeReviewCanvasLoadingState);
		const loadingStateBody = requireTestElement(
			BridgeReviewCanvasLoadingState({ reason: 'markdownPreview' }),
		);

		expect(findElementByComponent(element, BridgeMarkdownPreview)).toBeNull();
		expect(findElementByComponent(element, BridgeCodeViewPanel)).not.toBeNull();
		expect(loadingState).not.toBeNull();
		expect(loadingState?.props.reason).toBe('markdownPreview');
		expect(
			findElementByTestId(loadingStateBody, 'bridge-review-canvas-loading-state'),
		).not.toBeNull();
		expect(
			findElementsByTestId(loadingStateBody, 'bridge-review-canvas-loading-line'),
		).toHaveLength(3);
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
		expect(findElementByTestId(element, 'bridge-review-top-header')).toBeNull();
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
	readonly ariaPressed?: boolean;
	readonly children?: ReactNode;
	readonly className?: string;
	readonly 'data-bridge-segmented-control'?: string;
	readonly 'data-selected-content-state'?: string;
	readonly 'data-selected-display-path'?: string;
	readonly 'data-sidebar-position'?: string;
	readonly 'data-testid'?: string;
	readonly disabled?: boolean;
	readonly onClick?: () => void;
	readonly onValueChange?: () => void;
	readonly reason?: string;
	readonly role?: string;
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

function findElementsByTestId(
	node: ReactNode,
	testId: string,
): readonly ReactElement<TestElementProps>[] {
	if (Array.isArray(node)) {
		return node.flatMap((child: ReactNode): readonly ReactElement<TestElementProps>[] =>
			findElementsByTestId(child, testId),
		);
	}
	if (!isReactElement(node)) {
		return [];
	}
	return [
		...(node.props['data-testid'] === testId ? [node] : []),
		...findElementsByTestId(node.props.children, testId),
	];
}

function findElementsByType(
	node: ReactNode,
	type: string,
): readonly ReactElement<TestElementProps>[] {
	if (Array.isArray(node)) {
		return node.flatMap((child: ReactNode): readonly ReactElement<TestElementProps>[] =>
			findElementsByType(child, type),
		);
	}
	if (!isReactElement(node)) {
		return [];
	}
	return [...(node.type === type ? [node] : []), ...findElementsByType(node.props.children, type)];
}

function findElementByComponent(
	node: ReactNode,
	component: ReactElement['type'],
): ReactElement<TestElementProps> | null {
	if (Array.isArray(node)) {
		for (const child of node) {
			const match = findElementByComponent(child, component);
			if (match !== null) {
				return match;
			}
		}
		return null;
	}
	if (!isReactElement(node)) {
		return null;
	}
	if (node.type === component) {
		return node;
	}
	return findElementByComponent(node.props.children, component);
}

function findElementsByComponent(
	node: ReactNode,
	component: ReactElement['type'],
): readonly ReactElement<TestElementProps>[] {
	if (Array.isArray(node)) {
		return node.flatMap((child: ReactNode): readonly ReactElement<TestElementProps>[] =>
			findElementsByComponent(child, component),
		);
	}
	if (!isReactElement(node)) {
		return [];
	}
	return [
		...(node.type === component ? [node] : []),
		...findElementsByComponent(node.props.children, component),
	];
}

function classNameForElement(element: ReactElement<TestElementProps> | null): string {
	return element?.props.className ?? '';
}

function directChildControlNames(
	element: ReactElement<TestElementProps> | null,
): readonly (string | undefined)[] {
	if (element === null) {
		return [];
	}
	const children = Array.isArray(element.props.children)
		? element.props.children
		: [element.props.children];
	return children
		.filter(isReactElement)
		.map((child: ReactElement<TestElementProps>): string | undefined => {
			if (child.type === BridgeReviewProjectionMenu) {
				return 'BridgeReviewProjectionMenu';
			}
			return child.props['data-testid'];
		});
}

function projectionForPackage(
	reviewPackage: BridgeReviewPackage,
): ReturnType<typeof buildBridgeReviewProjection> {
	return buildBridgeReviewProjection({
		reviewPackage,
		request: { mode: { kind: 'normalReview' }, facets: [] },
	});
}
