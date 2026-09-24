import { useEffect } from 'react';
import { z } from 'zod';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import { bridgeProductIdentifierSchema } from '../core/comm-worker/bridge-product-contract-primitives.js';
import { bridgeFileCollectionSearchCriteriaSchema } from '../core/comm-worker/bridge-worker-file-collection-search-contracts.js';
import {
	useBridgeFileViewerCollectionSearch,
	type BridgeFileViewerCollectionSearchAnswer,
} from './bridge-file-viewer-collection-search-requests.js';

/**
 * Native collection search. Native dispatches this event and awaits the probe
 * promise in the same page call, so the answer is bound to that request on
 * this page. Search runs in the pane's comm worker over the File collection
 * rows; this seam only relays criteria in and the worker's answer out.
 */
export const bridgeNativeFilesSearchEventName = '__bridge_files_search';

export const bridgeNativeFilesSearchRequestSchema = z
	.object({
		criteria: bridgeFileCollectionSearchCriteriaSchema,
		requestId: bridgeProductIdentifierSchema,
	})
	.strict();

export interface BridgeNativeFilesSearchResult {
	readonly answer: BridgeFileViewerCollectionSearchAnswer;
	readonly requestId: string;
}

declare global {
	interface Window {
		bridgeFilesSearchProbe?: Promise<BridgeNativeFilesSearchResult>;
	}
}

export function searchBridgeFilesForNativeRequest(
	search: ReturnType<typeof useBridgeFileViewerCollectionSearch>,
	detail: unknown,
): Promise<BridgeNativeFilesSearchResult> | null {
	const request = bridgeNativeFilesSearchRequestSchema.safeParse(detail);
	if (!request.success) return null;
	return search(request.data.criteria).then(
		(answer): BridgeNativeFilesSearchResult => ({ answer, requestId: request.data.requestId }),
	);
}

export function useBridgeFileViewerNativeCollectionSearch(client: BridgePaneSurfaceClient): void {
	const search = useBridgeFileViewerCollectionSearch(client);
	useEffect((): (() => void) | undefined => {
		if (typeof window === 'undefined') return undefined;
		const handleSearchRequest = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const answer = searchBridgeFilesForNativeRequest(search, detail);
			if (answer === null) {
				delete window.bridgeFilesSearchProbe;
				return;
			}
			window.bridgeFilesSearchProbe = answer;
		};
		window.addEventListener(bridgeNativeFilesSearchEventName, handleSearchRequest);
		return (): void => {
			window.removeEventListener(bridgeNativeFilesSearchEventName, handleSearchRequest);
		};
	}, [search]);
}
