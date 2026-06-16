// @vitest-environment jsdom

import type { CodeViewScrollTarget } from '@pierre/diffs';
import type { ReactNode } from 'react';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { BridgeCodeViewPanel } from './bridge-code-view-panel.js';

const codeViewDoubles = vi.hoisted(() => ({
	addItems: vi.fn(),
	getInstanceRender: vi.fn(),
	getItem: vi.fn((id: string): unknown => ({ id })),
	scrollTo: vi.fn(),
	setSelectedLines: vi.fn(),
	updateItem: vi.fn((): boolean => true),
	updateItemId: vi.fn((): boolean => true),
}));

vi.mock('@pierre/diffs/react', async () => {
	const React = await vi.importActual<typeof import('react')>('react');
	const MockCodeView = React.forwardRef(function MockCodeView(
		_props: unknown,
		ref: React.ForwardedRef<unknown>,
	): React.ReactElement {
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
	});
});
