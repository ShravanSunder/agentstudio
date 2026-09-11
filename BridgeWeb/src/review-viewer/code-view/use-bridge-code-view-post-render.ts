import type { CodeViewOptions } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, useEffect, useMemo, type MutableRefObject } from 'react';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { createBridgeCodeViewPostRenderVisibleInterestPublisher } from './bridge-code-view-post-render-visible-interest.js';
import {
	observeBridgeCodeViewRenderFulfillment,
	type BridgeCodeViewRenderFulfillmentCoordinator,
} from './bridge-code-view-render-fulfillment.js';

export function useBridgeCodeViewPostRender(props: {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly publishVisibleItemIdsFromCurrentHandle: () => void;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderFulfillmentCoordinator;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[] | undefined;
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
			observeBridgeCodeViewRenderFulfillment({
				contextItem: context.item,
				getCodeViewHandle: (): CodeViewHandle<undefined> | null => props.codeViewHandleRef.current,
				itemId: context.item.id,
				phase,
				renderedElement: node,
				renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				selectedCodeViewItem: null,
				visibleCodeViewItems: props.visibleCodeViewItems,
			});
			visibleInterestPublisher.schedule();
		},
		[
			props.codeViewHandleRef,
			props.renderFulfillmentCoordinator,
			props.visibleCodeViewItems,
			visibleInterestPublisher,
		],
	);
	useEffect(
		(): (() => void) => (): void => visibleInterestPublisher.cancel(),
		[visibleInterestPublisher],
	);
	return handlePostRender;
}
