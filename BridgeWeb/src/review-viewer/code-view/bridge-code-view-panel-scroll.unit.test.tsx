// @vitest-environment jsdom

import type { CodeViewItem, CodeViewOptions, CodeViewScrollTarget } from '@pierre/diffs';
import type { ReactElement, ReactNode } from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { createBridgeCodeViewInitialItems } from './bridge-code-view-materialization.js';
import { BridgeCodeViewPanel, type BridgeCodeViewControlHandle } from './bridge-code-view-panel.js';
import { bridgePierreDarkThemeName } from './bridge-code-view-theme.js';

interface MockCodeViewProps {
	readonly initialItems?: readonly CodeViewItem[];
	readonly onScroll?: (
		scrollTop: number,
		viewer: { readonly getRenderedItems: () => readonly { readonly id: string }[] },
	) => void;
	readonly options?: CodeViewOptions<undefined>;
	readonly renderHeaderMetadata?: (item: CodeViewItem) => ReactNode;
	readonly renderHeaderPrefix?: (item: CodeViewItem) => ReactNode;
}

const codeViewDoubles = vi.hoisted(() => ({
	addItems: vi.fn(),
	containerElement: null as HTMLElement | null,
	getInstanceRender: vi.fn(),
	getItem: vi.fn((id: string): unknown => ({ id })),
	lastProps: null as MockCodeViewProps | null,
	renderedItems: [] as { readonly id: string }[],
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
			getInstance: (): {
				readonly getContainerElement: () => HTMLElement | undefined;
				readonly getRenderedItems: () => readonly { readonly id: string }[];
				readonly render: () => void;
			} => ({
				getContainerElement: (): HTMLElement | undefined =>
					codeViewDoubles.containerElement ?? undefined,
				getRenderedItems: (): readonly { readonly id: string }[] => codeViewDoubles.renderedItems,
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
	let mountedRoot: ReturnType<typeof createRoot> | null = null;

	beforeEach(() => {
		vi.clearAllMocks();
		codeViewDoubles.containerElement = null;
		codeViewDoubles.getItem.mockImplementation((id: string): unknown => ({ id }));
		codeViewDoubles.lastProps = null;
		codeViewDoubles.renderedItems = [];
	});

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		vi.restoreAllMocks();
		document.body.replaceChildren();
	});

	test('scrolls to a selected item when its content resources are ready on first mount', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
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
			request: { mode: { kind: 'normalReview' }, facets: [] },
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

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
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
		expect(document.querySelector('[data-testid="bridge-code-view-loading-state"]')).toBeNull();
		expect(codeViewDoubles.updateItem).not.toHaveBeenCalled();
	});

	test('defers selected item scrolling out of the React effect flush', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
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

		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalled();

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'source-high',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
	});

	test('uses Pierre smooth motion when mounted selection props change', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
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
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		codeViewDoubles.scrollTo.mockClear();

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

		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalled();

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'source-high',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalledWith({
			type: 'item',
			id: 'source-high',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
	});

	test('expands a prop-driven selected placeholder before smooth reveal', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
		});
		const initialCodeViewItems = createBridgeCodeViewInitialItems({
			projection,
			reviewPackage,
		});
		const placeholderItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'docs-plan',
		);
		if (placeholderItem === undefined) {
			throw new Error('expected docs-plan placeholder item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === 'docs-plan' ? placeholderItem : undefined,
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
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		codeViewDoubles.scrollTo.mockClear();
		codeViewDoubles.updateItem.mockClear();

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
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({
				id: 'docs-plan',
				collapsed: false,
			}),
		);
		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
	});

	test('smooth control-handle reveal delegates motion to Pierre without top-snap correction', async () => {
		const requestAnimationFrameSpy = vi
			.spyOn(window, 'requestAnimationFrame')
			.mockImplementation((): number => 1);
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const initialCodeViewItems = createBridgeCodeViewInitialItems({
			projection,
			reviewPackage,
		});
		const sourceHighCodeViewItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'source-high',
		);
		if (sourceHighCodeViewItem === undefined) {
			throw new Error('expected source-high initial CodeView item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): unknown =>
			id === 'source-high' ? sourceHighCodeViewItem : undefined,
		);
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		let controlHandle: BridgeCodeViewControlHandle | null = null;

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onControlHandleChange={(handle): void => {
						controlHandle = handle;
					}}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		requestAnimationFrameSpy.mockClear();
		codeViewDoubles.scrollTo.mockClear();

		let didReveal = false;
		await act(async (): Promise<void> => {
			didReveal = controlHandle?.scrollToItem('source-high', { behavior: 'smooth' }) ?? false;
			await Promise.resolve();
		});

		expect(didReveal).toBe(true);
		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'source-high',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
		expect(requestAnimationFrameSpy).not.toHaveBeenCalled();
	});

	test('keeps visible loading state inside CodeView items instead of floating a panel overlay', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{}}
					selectedItemId="source-high"
					visibleLoadingItemCount={3}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(
			document.querySelector('[data-testid="bridge-code-view-visible-loading-state"]'),
		).toBeNull();
	});

	test('passes compact DiffsHub-style CodeView options and review header renderers', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
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
		const headerPrefix = props?.renderHeaderPrefix?.(firstItem);
		expect(collectText(headerPrefix)).not.toContain('M');
		const headerContainer = document.createElement('div');
		document.body.append(headerContainer);
		const headerRoot = createRoot(headerContainer);
		await act(async (): Promise<void> => {
			headerRoot.render(<>{headerPrefix}</>);
			await Promise.resolve();
		});
		expect(
			headerContainer.querySelector('[data-testid="bridge-code-view-header-kind-icon"]'),
		).toBeNull();
		expect(
			headerContainer.querySelector('[data-testid="bridge-code-view-header-status"]'),
		).toBeNull();
		await act(async (): Promise<void> => {
			headerRoot.unmount();
			await Promise.resolve();
		});
		headerContainer.remove();
		expect(collectText(props?.renderHeaderMetadata?.(firstItem))).not.toContain(
			'Sources/App/Core.swift',
		);
		expect(collectText(props?.renderHeaderMetadata?.(firstItem))).toContain('+3');
		expect(collectText(props?.renderHeaderMetadata?.(firstItem))).toContain('-2');
	});

	test('file header prefix expands a placeholder as an inline loading item', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
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
		expect(collapseButton?.getAttribute('aria-expanded')).toBe('false');
		expect(collapseButton?.className).toContain('size-6');
		expect(collapseButton?.className).toContain('hover:border-[var(--bridge-border-opaque)]');

		await act(async (): Promise<void> => {
			collapseButton?.click();
			await Promise.resolve();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({
				id: firstItem.id,
				collapsed: false,
				bridgeMetadata: expect.objectContaining({ contentState: 'loading' }),
			}),
		);
		expect(codeViewDoubles.getInstanceRender).toHaveBeenCalled();

		await act(async (): Promise<void> => {
			headerRoot.unmount();
		});
	});

	test('file header collapse settles in-flight smooth selection motion before updating layout', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === firstItem.id ? firstItem : undefined,
		);
		const scrollOwner = document.createElement('div');
		scrollOwner.className = 'bridge-code-view-scroll-owner';
		scrollOwner.scrollTop = 240;
		const codeViewContainer = document.createElement('div');
		scrollOwner.append(codeViewContainer);
		document.body.append(scrollOwner);
		codeViewDoubles.containerElement = codeViewContainer;
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		let controlHandle: BridgeCodeViewControlHandle | null = null;

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onControlHandleChange={(handle): void => {
						controlHandle = handle;
					}}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		codeViewDoubles.scrollTo.mockClear();
		codeViewDoubles.updateItem.mockClear();

		let didStartSmoothReveal = false;
		await act(async (): Promise<void> => {
			didStartSmoothReveal =
				controlHandle?.scrollToItem(firstItem.id, { behavior: 'smooth' }) ?? false;
			await Promise.resolve();
		});
		expect(didStartSmoothReveal).toBe(true);
		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: firstItem.id,
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
		codeViewDoubles.scrollTo.mockClear();
		codeViewDoubles.updateItem.mockClear();

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
		await act(async (): Promise<void> => {
			collapseButton?.click();
			await Promise.resolve();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'position',
			position: 240,
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
		const settleScrollOrder = codeViewDoubles.scrollTo.mock.invocationCallOrder[0];
		const itemUpdateOrder = codeViewDoubles.updateItem.mock.invocationCallOrder[0];
		expect(settleScrollOrder).toBeLessThan(itemUpdateOrder ?? Number.POSITIVE_INFINITY);
		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({
				id: firstItem.id,
				collapsed: false,
				bridgeMetadata: expect.objectContaining({ contentState: 'loading' }),
			}),
		);

		await act(async (): Promise<void> => {
			headerRoot.unmount();
		});
	});

	test('keeps initial CodeView items stable across selected content hydration', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
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

	test('does not re-scroll the selected item when its content hydrates after initial reveal', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
		codeViewDoubles.scrollTo.mockClear();

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

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalled();
	});

	test('cancels stale instant header correction before a later smooth selection reveal', async () => {
		const animationFrameCallbacks: FrameRequestCallback[] = [];
		vi.spyOn(window, 'requestAnimationFrame').mockImplementation(
			(callback: FrameRequestCallback): number => {
				animationFrameCallbacks.push(callback);
				return animationFrameCallbacks.length;
			},
		);
		vi.spyOn(window, 'cancelAnimationFrame').mockImplementation((): void => {});
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const initialCodeViewItems = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const sourceHighItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'source-high',
		);
		const sourceNormalItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'source-normal',
		);
		if (sourceHighItem === undefined || sourceNormalItem === undefined) {
			throw new Error('expected source-high and source-normal CodeView items');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined => {
			if (id === 'source-high') {
				return sourceHighItem;
			}
			if (id === 'source-normal') {
				return sourceNormalItem;
			}
			return undefined;
		});
		const scrollOwner = document.createElement('div');
		scrollOwner.className = 'bridge-code-view-scroll-owner';
		scrollOwner.scrollTop = 100;
		Object.defineProperty(scrollOwner, 'getBoundingClientRect', {
			value: (): DOMRect => makeTestDOMRect({ top: 0 }),
		});
		const codeViewContainer = document.createElement('div');
		const staleHeader = document.createElement('div');
		staleHeader.dataset['diffsHeader'] = 'default';
		Object.defineProperty(staleHeader, 'getBoundingClientRect', {
			value: (): DOMRect => makeTestDOMRect({ top: 40 }),
		});
		const staleHeaderMarker = document.createElement('span');
		staleHeaderMarker.dataset['bridgeCodeViewItemId'] = 'source-high';
		staleHeader.append(staleHeaderMarker);
		codeViewContainer.append(staleHeader);
		scrollOwner.append(codeViewContainer);
		document.body.append(scrollOwner);
		codeViewDoubles.containerElement = codeViewContainer;
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
		const initialSelectionFrame = animationFrameCallbacks.shift();
		if (initialSelectionFrame === undefined) {
			throw new Error('expected initial selected-item RAF');
		}
		await act(async (): Promise<void> => {
			initialSelectionFrame(performance.now());
			await Promise.resolve();
		});
		expect(scrollOwner.scrollTop).toBe(140);
		const staleCorrectionFrame = animationFrameCallbacks.at(-1);
		if (staleCorrectionFrame === undefined) {
			throw new Error('expected stale header-correction RAF');
		}

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="source-normal"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			staleCorrectionFrame(performance.now());
			await Promise.resolve();
		});

		expect(scrollOwner.scrollTop).toBe(140);
	});

	test('smoothly re-reveals an explicitly revealed placeholder when it hydrates', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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
		const initialCodeViewItems = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const placeholderItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'docs-plan',
		);
		if (placeholderItem === undefined) {
			throw new Error('expected docs-plan placeholder item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === 'docs-plan' ? placeholderItem : undefined,
		);
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		let controlHandle: BridgeCodeViewControlHandle | null = null;

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onControlHandleChange={(handle): void => {
						controlHandle = handle;
					}}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		await act(async (): Promise<void> => {
			controlHandle?.scrollToItem('docs-plan', { behavior: 'smooth' });
			await Promise.resolve();
		});
		codeViewDoubles.scrollTo.mockClear();

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onControlHandleChange={(handle): void => {
						controlHandle = handle;
					}}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
	});

	test('preserves smooth selected placeholder reveal during hydration without top-snap correction', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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
		const initialCodeViewItems = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const placeholderItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'docs-plan',
		);
		if (placeholderItem === undefined) {
			throw new Error('expected docs-plan placeholder item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === 'docs-plan' ? placeholderItem : undefined,
		);
		const scrollOwner = document.createElement('div');
		scrollOwner.className = 'bridge-code-view-scroll-owner';
		scrollOwner.scrollTop = 100;
		const codeViewContainer = document.createElement('div');
		const headerAnchor = document.createElement('div');
		headerAnchor.dataset['bridgeCodeViewItemId'] = 'docs-plan';
		codeViewContainer.append(headerAnchor);
		scrollOwner.append(codeViewContainer);
		document.body.append(scrollOwner);
		codeViewDoubles.containerElement = codeViewContainer;
		vi.spyOn(scrollOwner, 'getBoundingClientRect').mockReturnValue({
			bottom: 600,
			height: 600,
			left: 0,
			right: 800,
			toJSON: () => ({}),
			top: 0,
			width: 800,
			x: 0,
			y: 0,
		} satisfies DOMRect);
		vi.spyOn(headerAnchor, 'getBoundingClientRect').mockImplementation((): DOMRect => {
			const top = -4 - (scrollOwner.scrollTop - 100);
			return {
				bottom: top + 32,
				height: 32,
				left: 0,
				right: 800,
				toJSON: () => ({}),
				top,
				width: 800,
				x: 0,
				y: top,
			} satisfies DOMRect;
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);
		let controlHandle: BridgeCodeViewControlHandle | null = null;

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onControlHandleChange={(handle): void => {
						controlHandle = handle;
					}}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		await act(async (): Promise<void> => {
			controlHandle?.scrollToItem('docs-plan', { behavior: 'smooth' });
			await Promise.resolve();
		});
		codeViewDoubles.scrollTo.mockClear();

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onControlHandleChange={(handle): void => {
						controlHandle = handle;
					}}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
		expect(scrollOwner.scrollTop).toBe(100);
	});

	test('keeps prop-driven smooth selection pending when content hydrates before the reveal frame', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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
		const initialCodeViewItems = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const placeholderItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'docs-plan',
		);
		if (placeholderItem === undefined) {
			throw new Error('expected docs-plan placeholder item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === 'docs-plan' ? placeholderItem : undefined,
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
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

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
		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalled();
		codeViewDoubles.scrollTo.mockClear();

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

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		expect(codeViewDoubles.scrollTo).not.toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
	});

	test('keeps prop-driven smooth selection in flight for collapse anchoring after reveal', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
		});
		const initialCodeViewItems = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		const placeholderItem = initialCodeViewItems.find(
			(item: CodeViewItem): boolean => item.id === 'docs-plan',
		);
		if (placeholderItem === undefined) {
			throw new Error('expected docs-plan placeholder item');
		}
		codeViewDoubles.getItem.mockImplementation((id: string): CodeViewItem | undefined =>
			id === 'docs-plan' ? placeholderItem : undefined,
		);
		const scrollOwner = document.createElement('div');
		scrollOwner.className = 'bridge-code-view-scroll-owner';
		scrollOwner.scrollTop = 100;
		const codeViewContainer = document.createElement('div');
		const headerAnchor = document.createElement('div');
		headerAnchor.dataset['bridgeCodeViewItemId'] = 'docs-plan';
		codeViewContainer.append(headerAnchor);
		scrollOwner.append(codeViewContainer);
		document.body.append(scrollOwner);
		codeViewDoubles.containerElement = codeViewContainer;
		vi.spyOn(scrollOwner, 'getBoundingClientRect').mockReturnValue({
			bottom: 600,
			height: 600,
			left: 0,
			right: 800,
			toJSON: () => ({}),
			top: 0,
			width: 800,
			x: 0,
			y: 0,
		} satisfies DOMRect);
		vi.spyOn(headerAnchor, 'getBoundingClientRect').mockImplementation((): DOMRect => {
			const top = -4 - (scrollOwner.scrollTop - 100);
			return {
				bottom: top + 32,
				height: 32,
				left: 0,
				right: 800,
				toJSON: () => ({}),
				top,
				width: 800,
				x: 0,
				y: top,
			} satisfies DOMRect;
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
					selectedItemId={null}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

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
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});
		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'item',
			id: 'docs-plan',
			align: 'start',
			behavior: 'smooth',
		} satisfies CodeViewScrollTarget);
		codeViewDoubles.scrollTo.mockClear();

		const headerContainer = document.createElement('div');
		document.body.append(headerContainer);
		const headerRoot = createRoot(headerContainer);
		await act(async (): Promise<void> => {
			headerRoot.render(<>{codeViewDoubles.lastProps?.renderHeaderPrefix?.(placeholderItem)}</>);
			await Promise.resolve();
		});
		const renderedCollapseButton = document.querySelector<HTMLButtonElement>(
			'[data-testid="bridge-code-view-header-collapse-button"]',
		);
		await act(async (): Promise<void> => {
			renderedCollapseButton?.click();
			await Promise.resolve();
		});

		expect(codeViewDoubles.scrollTo).toHaveBeenCalledWith({
			type: 'position',
			position: 100,
			behavior: 'instant',
		} satisfies CodeViewScrollTarget);
		expect(scrollOwner.scrollTop).toBe(100);
	});

	test('materializes selected content without depending on an animation frame', async () => {
		const requestAnimationFrameSpy = vi
			.spyOn(window, 'requestAnimationFrame')
			.mockImplementation((): number => 1);
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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

		expect(requestAnimationFrameSpy).toHaveBeenCalled();
		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		expect(codeViewPanel?.getAttribute('data-selected-materialized-update-result')).toBe('updated');
	});

	test('publishes the current Pierre rendered window for visible content hydration', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const onVisibleItemIdsChange = vi.fn();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onVisibleItemIdsChange={onVisibleItemIdsChange}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="source-high"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		onVisibleItemIdsChange.mockClear();
		codeViewDoubles.lastProps?.onScroll?.(128, {
			getRenderedItems: (): readonly { readonly id: string }[] => [
				{ id: 'source-high' },
				{ id: 'source-normal' },
				{ id: 'source-normal' },
			],
		});

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(onVisibleItemIdsChange).toHaveBeenCalledWith(['source-high', 'source-normal']);
	});

	test('publishes a union of visible headers and Pierre rendered items for hydration', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const [firstItem] = createBridgeCodeViewInitialItems({ reviewPackage, projection });
		if (firstItem === undefined) {
			throw new Error('expected initial CodeView item');
		}
		const onVisibleItemIdsChange = vi.fn();
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					onVisibleItemIdsChange={onVisibleItemIdsChange}
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={null}
					selectedItemId="source-high"
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
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});
		onVisibleItemIdsChange.mockClear();

		codeViewDoubles.lastProps?.onScroll?.(128, {
			getRenderedItems: (): readonly { readonly id: string }[] => [
				{ id: 'source-normal' },
				{ id: 'test-view' },
			],
		});

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(onVisibleItemIdsChange).toHaveBeenLastCalledWith([
			'source-high',
			'source-normal',
			'test-view',
		]);

		await act(async (): Promise<void> => {
			headerRoot.unmount();
		});
		headerContainer.remove();
	});

	test('materializes visible non-selected item resources without routing them through selection', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const visibleItem = reviewPackage.itemsById['source-normal'];
		const headHandle = visibleItem?.contentRoles.head;
		if (visibleItem === undefined || headHandle === undefined || headHandle === null) {
			throw new Error('expected source-normal head handle');
		}
		const visibleContentResource: BridgeContentResource = {
			handle: headHandle,
			text: 'let visibleWindowHydrated = true',
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
					selectedItemId="source-high"
					visibleContentResourcesByItemId={
						new Map([['source-normal', { head: visibleContentResource }]])
					}
					visibleReadyItemCount={1}
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'source-normal' }),
		);
		const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		expect(codeViewPanel?.getAttribute('data-code-view-rendered-content-resource-count')).toBe('1');
		expect(codeViewPanel?.getAttribute('data-code-view-visible-ready-item-count')).toBe('1');
		expect(codeViewPanel?.getAttribute('data-selected-materialized-update-result')).toBe('not-run');
	});

	test('materializes selected content loading inline before visible hydration reports the row', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentLoadingItemId="docs-plan"
					selectedContentResources={null}
					selectedItemId="docs-plan"
					workerPoolEnabled={false}
				/>,
			);
			await Promise.resolve();
		});

		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({
				id: 'docs-plan',
				bridgeMetadata: expect.objectContaining({ contentState: 'loading' }),
			}),
		);
	});

	test('materializes selected content during the post-commit effect before animation frames', async () => {
		const animationFrameCallbacks: FrameRequestCallback[] = [];
		vi.spyOn(window, 'requestAnimationFrame').mockImplementation(
			(callback: FrameRequestCallback): number => {
				animationFrameCallbacks.push(callback);
				return animationFrameCallbacks.length;
			},
		);
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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
		codeViewDoubles.updateItem.mockClear();

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

		expect(codeViewDoubles.updateItem).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'docs-plan' }),
		);
		expect(animationFrameCallbacks.length).toBeGreaterThan(0);
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
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
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
		expect(requestAnimationFrameSpy).toHaveBeenCalled();

		await act(async (): Promise<void> => {
			for (const animationFrameCallback of animationFrameCallbacks) {
				animationFrameCallback(performance.now());
			}
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

function makeTestDOMRect(props: { readonly top: number }): DOMRect {
	return {
		bottom: props.top,
		height: 0,
		left: 0,
		right: 0,
		toJSON: (): Record<string, number> => ({}),
		top: props.top,
		width: 0,
		x: 0,
		y: props.top,
	};
}

async function waitForAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => {
			resolve();
		});
	});
}

function isReactElementWithChildren(
	node: ReactNode,
): node is ReactElement<{ readonly children?: ReactNode }> {
	return typeof node === 'object' && node !== null && 'props' in node;
}
