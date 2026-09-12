import {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
	type Dispatch,
	type SetStateAction,
} from 'react';

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
			readonly refresh:
				| { readonly kind: 'current' }
				| { readonly kind: 'pending' }
				| { readonly kind: 'failed' };
	  }
	| { readonly status: 'failed'; readonly sourcePath: string };

export function useBridgeMarkdownPresentation(props: {
	readonly abortKey: string;
	readonly isActive: boolean;
	readonly intent: BridgeMarkdownRenderIntent | null;
	readonly selectedPath: string | null;
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
	const completedIntentKeyRef = useRef<string | null>(null);
	const completedSourcePathRef = useRef<string | null>(null);

	useEffect((): (() => void) | void => {
		if (!props.isActive) {
			props.workerClient?.abort(props.abortKey);
			return;
		}
		const intent = latestIntentRef.current;
		if (intent === null || intentKey === null) {
			props.workerClient?.abort(props.abortKey);
			if (completedSourcePathRef.current !== props.selectedPath)
				completedIntentKeyRef.current = null;
			setPresentationState((current) =>
				current.status === 'ready' && current.sourcePath === props.selectedPath
					? { ...current, refresh: { kind: 'pending' } }
					: { status: 'idle' },
			);
			return;
		}
		if (completedIntentKeyRef.current === intentKey) {
			setPresentationState((current) =>
				current.status === 'ready' ? { ...current, refresh: { kind: 'current' } } : current,
			);
			return;
		}
		completedIntentKeyRef.current = null;
		setPresentationState((current) =>
			current.status === 'ready' && current.sourcePath === intent.sourcePath
				? { ...current, refresh: { kind: 'pending' } }
				: { status: 'loading', sourcePath: intent.sourcePath },
		);
		if (props.workerClient === null) {
			setPresentationState((current) => failedMarkdownPresentation(current, intent.sourcePath));
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
			if (completion.status === 'success') {
				completedIntentKeyRef.current = intentKey;
				completedSourcePathRef.current = intent.sourcePath;
			}
			applyBridgeMarkdownCompletion({ completion, intent, setPresentationState });
		});
		return (): void => {
			acceptsCompletion = false;
			workerClient.abort(props.abortKey);
		};
	}, [
		intentKey,
		props.abortKey,
		props.isActive,
		props.selectedPath,
		props.workerClient,
		retryRevision,
	]);

	const retry = useCallback((): void => setRetryRevision((revision): number => revision + 1), []);
	return { presentationState, retry };
}

function applyBridgeMarkdownCompletion(props: {
	readonly completion: BridgeMarkdownRenderWorkerClientCompletion;
	readonly intent: BridgeMarkdownRenderIntent;
	readonly setPresentationState: Dispatch<SetStateAction<BridgeMarkdownPresentationState>>;
}): void {
	if (props.completion.status === 'stale') {
		return;
	}
	if (props.completion.status === 'failure') {
		props.setPresentationState((current) =>
			failedMarkdownPresentation(current, props.intent.sourcePath),
		);
		return;
	}
	props.setPresentationState({
		status: 'ready',
		refresh: { kind: 'current' },
		sourcePath: props.intent.sourcePath,
		identity: props.completion.identity,
		renderResult: props.completion.response,
	});
}

function failedMarkdownPresentation(
	current: BridgeMarkdownPresentationState,
	sourcePath: string,
): BridgeMarkdownPresentationState {
	return current.status === 'ready' && current.sourcePath === sourcePath
		? { ...current, refresh: { kind: 'failed' } }
		: { status: 'failed', sourcePath };
}

function bridgeMarkdownIntentKey(intent: BridgeMarkdownRenderIntent): string {
	return JSON.stringify({
		sourceIdentity: intent.sourceIdentity,
		sourcePath: intent.sourcePath,
		contentCacheKey: intent.contentCacheKey,
		contentHash: intent.contentHash,
	});
}
