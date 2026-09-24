import { useCallback, useEffect, useRef } from 'react';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeFileCollectionSearchOutcome,
	BridgeFileCollectionSearchWireCriteria,
} from '../core/comm-worker/bridge-worker-file-collection-search-contracts.js';

/**
 * Why a collection search produced no worker answer. `refused` covers a worker
 * that rejected the command or was replaced before answering; the pane runtime
 * reports both as a degraded health event for the request.
 */
export type BridgeFileViewerCollectionSearchUnavailableReason = 'disposed' | 'refused' | 'timedOut';

export type BridgeFileViewerCollectionSearchAnswer =
	| BridgeFileCollectionSearchOutcome
	| {
			readonly kind: 'unavailable';
			readonly reason: BridgeFileViewerCollectionSearchUnavailableReason;
	  };

export interface BridgeFileViewerCollectionSearchRequests {
	readonly dispose: () => void;
	readonly search: (
		criteria: BridgeFileCollectionSearchWireCriteria,
	) => Promise<BridgeFileViewerCollectionSearchAnswer>;
}

/**
 * Correlates File collection searches with the mounted worker's answers. Every
 * search settles exactly once: with the worker's outcome, or unavailable when
 * the worker refuses or never answers the command, or the viewer unmounts.
 */
export function createBridgeFileViewerCollectionSearchRequests(props: {
	readonly client: BridgePaneSurfaceClient;
}): BridgeFileViewerCollectionSearchRequests {
	const pendingResolveByRequestId = new Map<
		string,
		(answer: BridgeFileViewerCollectionSearchAnswer) => void
	>();
	let isDisposed = false;
	/** Answers delivered while `send` is still on the stack, before the request id is known. */
	let answersDuringSend: Map<string, BridgeFileViewerCollectionSearchAnswer> | null = null;

	const settle = (requestId: string, answer: BridgeFileViewerCollectionSearchAnswer): void => {
		const resolve = pendingResolveByRequestId.get(requestId);
		if (resolve === undefined) {
			answersDuringSend?.set(requestId, answer);
			return;
		}
		pendingResolveByRequestId.delete(requestId);
		resolve(answer);
	};
	const settleEveryPending = (reason: BridgeFileViewerCollectionSearchUnavailableReason): void => {
		for (const requestId of pendingResolveByRequestId.keys()) {
			settle(requestId, { kind: 'unavailable', reason });
		}
	};

	const unsubscribeMessages = props.client.subscribeMessages((message): void => {
		if (message.kind === 'fileCollectionSearch') {
			settle(message.requestId, message.outcome);
			return;
		}
		if (
			message.kind === 'health' &&
			message.status === 'degraded' &&
			message.requestId !== undefined
		) {
			settle(message.requestId, { kind: 'unavailable', reason: 'refused' });
		}
	});
	const unsubscribeLifecycle = props.client.lifecycle.subscribe((): void => {
		const requestsById = props.client.lifecycle.getSnapshot().requestsById;
		for (const requestId of pendingResolveByRequestId.keys()) {
			if (requestsById[requestId]?.state === 'timed_out') {
				settle(requestId, { kind: 'unavailable', reason: 'timedOut' });
			}
		}
	});

	return {
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			unsubscribeMessages();
			unsubscribeLifecycle();
			settleEveryPending('disposed');
		},
		search: (criteria): Promise<BridgeFileViewerCollectionSearchAnswer> => {
			if (isDisposed) {
				return Promise.resolve({ kind: 'unavailable', reason: 'disposed' });
			}
			const earlyAnswers = new Map<string, BridgeFileViewerCollectionSearchAnswer>();
			answersDuringSend = earlyAnswers;
			let requestId: string;
			try {
				requestId = props.client.send({
					command: 'fileCollectionSearch',
					criteria,
					// A search is a read outside intent-epoch admission; its request id correlates it.
					epoch: 0,
				});
			} catch {
				return Promise.resolve({ kind: 'unavailable', reason: 'refused' });
			} finally {
				answersDuringSend = null;
			}
			const earlyAnswer = earlyAnswers.get(requestId);
			if (earlyAnswer !== undefined) return Promise.resolve(earlyAnswer);
			return new Promise<BridgeFileViewerCollectionSearchAnswer>((resolve): void => {
				pendingResolveByRequestId.set(requestId, resolve);
			});
		},
	};
}

/**
 * The File surface's collection search, bound to the pane's surface client for
 * the lifetime of the component. A search issued after unmount is unavailable.
 */
export function useBridgeFileViewerCollectionSearch(
	client: BridgePaneSurfaceClient,
): (
	criteria: BridgeFileCollectionSearchWireCriteria,
) => Promise<BridgeFileViewerCollectionSearchAnswer> {
	const requestsRef = useRef<BridgeFileViewerCollectionSearchRequests | null>(null);
	useEffect((): (() => void) => {
		const requests = createBridgeFileViewerCollectionSearchRequests({ client });
		requestsRef.current = requests;
		return (): void => {
			if (requestsRef.current === requests) requestsRef.current = null;
			requests.dispose();
		};
	}, [client]);
	return useCallback(
		(criteria): Promise<BridgeFileViewerCollectionSearchAnswer> =>
			requestsRef.current?.search(criteria) ??
			Promise.resolve({ kind: 'unavailable', reason: 'disposed' }),
		[],
	);
}
