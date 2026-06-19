// @vitest-environment jsdom

import type { CodeViewItem, CodeViewOptions, CodeViewScrollTarget } from '@pierre/diffs';
import type { ReactElement, ReactNode } from 'react';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { createBridgeCodeViewInitialItems } from './bridge-code-view-materialization.js';
import { BridgeCodeViewPanel } from './bridge-code-view-panel.js';
import { bridgePierreDarkThemeName } from './bridge-code-view-theme.js';

interface MockCodeViewProps {
	readonly initialItems?: readonly CodeViewItem[];
	readonly options?: CodeViewOptions<undefined>;
	readonly renderHeaderMetadata?: (item: CodeViewItem) => ReactNode;
	readonly renderHeaderPrefix?: (item: CodeViewItem) => ReactNode;
}

const codeViewDoubles = vi.hoisted(() => ({
	addItems: vi.fn(),
	getInstanceRender: vi.fn(),
	getItem: vi.fn((id: string): unknown => ({ id })),
	lastProps: null as MockCodeViewProps | null,
	scrollTo: vi.fn(),
	setSelectedLines: vi.fn(),
	updateItem: vi.fn((): boolean => true),
	updateItemId: vi.fn((): boolean => true),
}));

vi.mock('@pierre/diffs/react', async () => {
	const React = await vi.importActual<typeof import('react')>('react');
	const MockCodeView = React.forwardRef(function MockCodeView(
		props: MockCodeViewProps,
		ref: React.ForwardedRef<unknown>,
	): React.ReactElement {
		codeViewDoubles.lastProps = props;
		React.useImperativeHandle(ref, () => ({
			addItems: codeViewDoubles.addItems,
			getInstance: (): { readonly render: () => void } => ({
				render: codeViewDoubles.getInstanceRender,
			}),
			getItem: codeViewDoubles.getItem,
			scrollTo: codeViewDoubles.scrollTo,
			setSelectedLines: codeViewDoubles.setSelectedLines,
			updateItem: codeViewDoubles.updateItem,
			updateItemId: codeViewDoubles.updateItemId,
		}));
		return React.createElement('div', { 'data-testid': 'mock-code-view' });
	});

	return {
		CodeView: MockCodeView,
		WorkerPoolContextProvider: (props: { readonly children: ReactNode }): React.ReactElement =>
			React.createElement(React.Fragment, null, props.children),
		useWorkerPool: (): null => null,
	};
});

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeCodeViewPanel initial selection scroll', () => {
	let mountedRoot: Root | null = null;

	beforeEach(() => {
		vi.clearAllMocks();
		codeViewDoubles.getItem.mockImplementation((id: string): unknown => ({ id }));
		codeViewDoubles.lastProps = null;
	});

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
	});

	test('scrolls to a selected item when its content resources are ready on first mount', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'docsAndPlans' }, refinements: [] },
		});
		const selectedItem = reviewPackage.itemsById['docs-plan'];
		const headHandle = selectedItem?.contentRoles.head;
		if (selectedItem === undefined || headHandle === undefined || headHandle === null) {
			throw new Error('expected docs-plan head handle');
		}
		const selectedContentResource: BridgeContentResource = {
			handle: headHandle,
			text: '# Bridge plan\n\nInspect this as source.',
		};
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
		const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		expect(codeViewPanel?.getAttribute('data-selected-content-character-count')).toBe('38');
		expect(codeViewPanel?.getAttribute('data-selected-content-line-count')).toBe('3');
		expect(codeViewPanel?.getAttribute('data-selected-content-cache-key-count')).toBe('1');
	});

	test('scrolls to a selected placeholder item before its content resources hydrate', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'allFiles' }, refinements: [] },
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="source-high"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'source-high',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
		const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		expect(codeViewPanel?.getAttribute('data-selected-item-id')).toBe('source-high');
		expect(codeViewPanel?.getAttribute('data-selected-display-path')).toBe(
			'Sources/App/Core.swift',
		);
		expect(codeViewPanel?.getAttribute('data-selected-content-character-count')).toBe('0');
		expect(codeViewPanel?.getAttribute('data-selected-content-line-count')).toBe('0');
		expect(codeViewPanel?.getAttribute('data-selected-content-cache-key-count')).toBe('0');
		expect(codeViewDoubles.updateItem).not.toHaveBeenCalled();
	});

	test('passes compact DiffsHub-style CodeView options and review header renderers', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'allFiles' }, refinements: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="source-high"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		const props = codeViewDoubles.lastProps;
		expect(props?.options).toMatchObject({
			diffStyle: 'split',
			diffIndicators: 'bars',
			hunkSeparators: 'line-info-basic',
			lineDiffType: 'word',
			overflow: 'scroll',
			stickyHeaders: true,
			theme: {
				dark: bridgePierreDarkThemeName,
				light: bridgePierreDarkThemeName,
			},
			themeType: 'dark',
			layout: {
				paddingTop: 0,
				paddingBottom: 0,
				gap: 1,
			},
		});
		expect(props?.options?.unsafeCSS).toContain('data-diffs-header');
		expect(props?.renderHeaderPrefix).toEqual(expect.any(Function));
		expect(props?.renderHeaderMetadata).toEqual(expect.any(Function));
		expect(collectText(props?.renderHeaderPrefix?.(firstItem))).toContain('M');
		expect(collectText(props?.renderHeaderMetadata?.(firstItem))).toContain(
			'Sources/App/Core.swift',
		);
		expect(collectText(props?.renderHeaderMetadata?.(firstItem))).toContain('+3');
		expect(collectText(props?.renderHeaderMetadata?.(firstItem))).toContain('-2');
	});

	test('file header prefix toggles Pierre item collapse with a new item version', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'allFiles' }, refinements: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === firstItem.id ? firstItem : undefined,
		);
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId={firstItem.id}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		const headerContainer = document.createElement('div');
		document.body.append(headerContainer);
		const headerRoot = createRoot(headerContainer);
		await act(async (): Promise<void> => {
			headerRoot.render(<>{codeViewDoubles.lastProps?.renderHeaderPrefix?.(firstItem)}</>);
			await Promise.resolve();
		});

		const collapseButton = headerContainer.querySelector<HTMLButtonElement>(
			'[data-testid="bridge-code-view-header-collapse-button"]',
		);
		expect(collapseButton).not.toBeNull();
		expect(collapseButton?.getAttribute('aria-expanded')).toBe('true');

		await act(async (): Promise<void> => {
			collapseButton?.click();
			await Promise.resolve();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith({
			...firstItem,
			collapsed: true,
			version: (firstItem.version ?? 0) + 1,
		});
		expect(codeViewDoubles.getInstanceRender).toHaveBeenCalled();

		await act(async (): Promise<void> => {
			headerRoot.unmount();
		});
	});

	test('keeps initial CodeView items stable across selected content hydration', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'docsAndPlans' }, refinements: [] },
		});
		const selectedItem = reviewPackage.itemsById['docs-plan'];
		const headHandle = selectedItem?.contentRoles.head;
		if (selectedItem === undefined || headHandle === undefined || headHandle === null) {
			throw new Error('expected docs-plan head handle');
		}
		const selectedContentResource: BridgeContentResource = {
			handle: headHandle,
			text: '# Bridge plan\n\nInspect this as source.',
		};
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		const initialItems = codeViewDoubles.lastProps?.initialItems;
		if (initialItems === undefined) {
			throw new Error('expected CodeView initial items');
		}

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(codeViewDoubles.lastProps?.initialItems).toBe(initialItems);
		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		expect(codeViewPanel?.getAttribute('data-selected-materialized-update-result')).toBe('updated');
		expect(codeViewPanel?.getAttribute('data-selected-materialized-item-type')).toBe('diff');
		expect(
			Number(codeViewPanel?.getAttribute('data-selected-materialized-item-version')),
		).toBeGreaterThan(0);
		expect(
			Number(codeViewPanel?.getAttribute('data-selected-materialized-addition-line-count')),
		).toBeGreaterThan(0);
	});

	test('runs a deferred CodeView render after selected content materializes', async () => {
		const animationFrameCallbacks: FrameRequestCallback[] = [];
		const requestAnimationFrameSpy = vi
			.spyOn(window, 'requestAnimationFrame')
			.mockImplementation((callback: FrameRequestCallback): number => {
				animationFrameCallbacks.push(callback);
				return animationFrameCallbacks.length;
			});
		vi.spyOn(window, 'cancelAnimationFrame').mockImplementation((): void => {});
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'docsAndPlans' }, refinements: [] },
		});
		const selectedItem = reviewPackage.itemsById['docs-plan'];
		const headHandle = selectedItem?.contentRoles.head;
		if (selectedItem === undefined || headHandle === undefined || headHandle === null) {
			throw new Error('expected docs-plan head handle');
		}
		const selectedContentResource: BridgeContentResource = {
			handle: headHandle,
			text: '# Bridge plan\n\nInspect this as source.',
		};
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		codeViewDoubles.getInstanceRender.mockClear();

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(codeViewDoubles.getInstanceRender).toHaveBeenCalledTimes(1);
		expect(requestAnimationFrameSpy).toHaveBeenCalledTimes(1);

		await act(async (): Promise<void> => {
			animationFrameCallbacks[0]?.(performance.now());
			await Promise.resolve();
		});

		expect(codeViewDoubles.getInstanceRender).toHaveBeenCalledTimes(2);
		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
	});
});

function collectText(node: ReactNode): string {
	if (node === null || node === undefined || typeof node === 'boolean') {
		return '';
	}
	if (typeof node === 'string' || typeof node === 'number') {
		return String(node);
	}
	if (Array.isArray(node)) {
		return node.map((child: ReactNode): string => collectText(child)).join(' ');
	}
	if (isReactElementWithChildren(node)) {
		return collectText(node.props.children);
	}
	return '';
}

function isReactElementWithChildren(
	node: ReactNode,
): node is ReactElement<{ readonly children?: ReactNode }> {
	return typeof node === 'object' && node !== null && 'props' in node;
}
