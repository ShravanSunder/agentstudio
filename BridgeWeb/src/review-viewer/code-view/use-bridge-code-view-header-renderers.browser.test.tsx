import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, renderHook } from 'vitest-browser-react';

import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import type { BridgeCodeViewItemPresentation } from './bridge-code-view-materialization.js';
import { useBridgeCodeViewHeaderRenderers } from './use-bridge-code-view-header-renderers.js';

describe('useBridgeCodeViewHeaderRenderers', () => {
	afterEach(async () => cleanup());

	test('keeps renderer identity stable when only selected presentation changes', async () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const collapsedItemIds = new Set<string>();
		const onHeaderVisibilityChange = (): void => {};
		const onToggleItemCollapse = (): void => {};
		const onFilePresentationChange = (): void => {};
		type HeaderRendererHookProps = {
			readonly selectedItemId: string | null;
			readonly selectedItemPresentation: BridgeCodeViewItemPresentation | null;
		};
		const hook = await renderHook<
			HeaderRendererHookProps,
			ReturnType<typeof useBridgeCodeViewHeaderRenderers>
		>(
			(props) => {
				if (props === undefined) throw new Error('expected header renderer hook props');
				return useBridgeCodeViewHeaderRenderers({
					collapsedItemIds,
					onFilePresentationChange,
					onHeaderVisibilityChange,
					onToggleItemCollapse,
					reviewPackage,
					selectedItemId: props.selectedItemId,
					selectedItemPresentation: props.selectedItemPresentation,
				});
			},
			{
				initialProps: {
					selectedItemId: 'docs-plan',
					selectedItemPresentation: null,
				} satisfies HeaderRendererHookProps,
			},
		);
		const diffRenderers = hook.result.current;

		await hook.rerender({
			selectedItemId: 'docs-plan',
			selectedItemPresentation: { kind: 'file', version: 'current' },
		});

		expect(hook.result.current).toBe(diffRenderers);
	});
});
