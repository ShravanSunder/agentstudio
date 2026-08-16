import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type {
	BridgeMarkdownRenderWorkerClient,
	BridgeMarkdownRenderWorkerClientCompletion,
} from './worker/bridge-markdown-render-worker-client.js';
import type {
	BridgeMarkdownRenderRequestIdentity,
	BridgeMarkdownRenderWorkerSuccessResponse,
	BridgeMarkdownSourceIdentity,
} from './worker/bridge-markdown-render-worker-rpc.js';

export interface BridgeMarkdownRenderIntent {
	readonly sourceIdentity: BridgeMarkdownSourceIdentity;
	readonly sourcePath: string;
	readonly contentCacheKey: string;
	readonly contentHash: string;
	readonly markdownText: string;
}

export type BridgeMarkdownPresentationState =
	| { readonly status: 'idle' }
	| { readonly status: 'loading'; readonly sourcePath: string }
	| {
			readonly status: 'ready';
			readonly sourcePath: string;
			readonly identity: BridgeMarkdownRenderRequestIdentity;
			readonly renderResult: BridgeMarkdownRenderWorkerSuccessResponse;
	  }
	| { readonly status: 'failed'; readonly sourcePath: string };

export function useBridgeMarkdownPresentation(props: {
	readonly abortKey: string;
	readonly intent: BridgeMarkdownRenderIntent | null;
	readonly workerClient: BridgeMarkdownRenderWorkerClient | null;
}): {
	readonly presentationState: BridgeMarkdownPresentationState;
	readonly retry: () => void;
} {
	const [retryRevision, setRetryRevision] = useState(0);
	const [presentationState, setPresentationState] = useState<BridgeMarkdownPresentationState>({
		status: 'idle',
	});
	const intentKey = useMemo(
		(): string | null => (props.intent === null ? null : bridgeMarkdownIntentKey(props.intent)),
		[props.intent],
	);
	const latestIntentRef = useRef(props.intent);
	latestIntentRef.current = props.intent;

	useEffect((): (() => void) | void => {
		const intent = latestIntentRef.current;
		if (intent === null || intentKey === null) {
			props.workerClient?.abort(props.abortKey);
			setPresentationState({ status: 'idle' });
			return;
		}
		setPresentationState({ status: 'loading', sourcePath: intent.sourcePath });
		if (props.workerClient === null) {
			setPresentationState({ status: 'failed', sourcePath: intent.sourcePath });
			return;
		}
		const workerClient = props.workerClient;
		let acceptsCompletion = true;
		const task = workerClient.startRender({
			sourceIdentity: intent.sourceIdentity,
			contentCacheKey: intent.contentCacheKey,
			contentHash: intent.contentHash,
			markdownText: intent.markdownText,
			sourcePath: intent.sourcePath,
			abortKey: props.abortKey,
		});
		void task.completed.then((completion): void => {
			if (!acceptsCompletion) {
				return;
			}
			applyBridgeMarkdownCompletion({ completion, intent, setPresentationState });
		});
		return (): void => {
			acceptsCompletion = false;
			workerClient.abort(props.abortKey);
		};
	}, [intentKey, props.abortKey, props.workerClient, retryRevision]);

	const retry = useCallback((): void => setRetryRevision((revision): number => revision + 1), []);
	return { presentationState, retry };
}

function applyBridgeMarkdownCompletion(props: {
	readonly completion: BridgeMarkdownRenderWorkerClientCompletion;
	readonly intent: BridgeMarkdownRenderIntent;
	readonly setPresentationState: (state: BridgeMarkdownPresentationState) => void;
}): void {
	if (props.completion.status === 'stale') {
		return;
	}
	if (props.completion.status === 'failure') {
		props.setPresentationState({ status: 'failed', sourcePath: props.intent.sourcePath });
		return;
	}
	props.setPresentationState({
		status: 'ready',
		sourcePath: props.intent.sourcePath,
		identity: props.completion.identity,
		renderResult: props.completion.response,
	});
}

function bridgeMarkdownIntentKey(intent: BridgeMarkdownRenderIntent): string {
	return JSON.stringify({
		sourceIdentity: intent.sourceIdentity,
		sourcePath: intent.sourcePath,
		contentCacheKey: intent.contentCacheKey,
		contentHash: intent.contentHash,
	});
}
