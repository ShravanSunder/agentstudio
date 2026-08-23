import type { CodeViewOptions } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, useEffect, useMemo, type MutableRefObject } from 'react';

import { isBridgeCodeViewItem } from './bridge-code-view-panel-support.js';
import { createBridgeCodeViewPostRenderVisibleInterestPublisher } from './bridge-code-view-post-render-visible-interest.js';
import {
	observeBridgeCodeViewRenderFulfillment,
	type BridgeCodeViewRenderFulfillmentCoordinator,
} from './bridge-code-view-render-fulfillment.js';

export function useBridgeCodeViewPostRender(props: {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly publishVisibleItemIdsFromCurrentHandle: () => void;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderFulfillmentCoordinator;
}): NonNullable<CodeViewOptions<undefined>['onPostRender']> {
	const visibleInterestPublisher = useMemo(
		() =>
			createBridgeCodeViewPostRenderVisibleInterestPublisher({
				publishSettledWindow: props.publishVisibleItemIdsFromCurrentHandle,
				queueMicrotask: (callback): void => globalThis.queueMicrotask(callback),
			}),
		[props.publishVisibleItemIdsFromCurrentHandle],
	);
	const handlePostRender = useCallback<NonNullable<CodeViewOptions<undefined>['onPostRender']>>(
		(node, _instance, phase, context): void => {
			const exactPresentationItem = isBridgeCodeViewItem(context.item) ? context.item : null;
			observeBridgeCodeViewRenderFulfillment({
				contextItem: context.item,
				getCodeViewHandle: (): CodeViewHandle<undefined> | null => props.codeViewHandleRef.current,
				itemId: context.item.id,
				phase,
				renderedElement: node,
				renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				selectedCodeViewItem: exactPresentationItem,
				visibleCodeViewItems: undefined,
			});
			visibleInterestPublisher.schedule();
		},
		[props.codeViewHandleRef, props.renderFulfillmentCoordinator, visibleInterestPublisher],
	);
	useEffect(
		(): (() => void) => (): void => visibleInterestPublisher.cancel(),
		[visibleInterestPublisher],
	);
	return handlePostRender;
}
