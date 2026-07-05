import { act } from 'react';

import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { waitForBridgeViewerAnimationFrame } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';

export interface DispatchHostAdmittedReviewIntakeFrameOptions {
	readonly telemetryConfig?: unknown;
}

export async function dispatchHostAdmittedReviewIntakeFrame(
	frame: BridgeIntakeFrame,
	options: DispatchHostAdmittedReviewIntakeFrameOptions = {},
): Promise<void> {
	await act(async (): Promise<void> => {
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: { pushNonce: 'push-nonce', telemetryConfig: options.telemetryConfig },
			}),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(frame),
					nonce: 'push-nonce',
				},
			}),
		);
		await Promise.resolve();
		await waitForBridgeViewerAnimationFrame();
	});
}

export async function dispatchHostDiffStatus(props: {
	readonly epoch: number;
	readonly revision: number;
	readonly status: 'idle' | 'loading' | 'ready' | 'error';
	readonly error?: string | null;
}): Promise<void> {
	await act(async (): Promise<void> => {
		document.dispatchEvent(
			new CustomEvent('__bridge_push_json', {
				detail: {
					json: JSON.stringify({
						__v: 1,
						__pushId: `push-${props.epoch}-${props.revision}`,
						__revision: props.revision,
						__epoch: props.epoch,
						store: 'diff',
						op: 'replace',
						level: 'hot',
						slice: 'diff_status',
						data: {
							status: props.status,
							error: props.error ?? null,
							epoch: props.epoch,
						},
					}),
					nonce: 'push-nonce',
				},
			}),
		);
		await Promise.resolve();
		await waitForBridgeViewerAnimationFrame();
	});
}

/**
 * This app mounts real resizable-panel chrome (ResizeObserver-driven layout
 * settling), review/file surfaces with real code-diff/tree custom elements,
 * and drives everything through native-shaped CustomEvents rather than direct
 * prop/state calls. React updates land continuously — after every dispatched
 * frame, after every click, and from background layout settling in between.
 * `expect.poll(...)` alone re-checks the DOM on a real-timer interval without
 * ever opening an `act()` scope, so every one of those updates fires outside
 * of `act()`. Poll from inside a real-timer act() loop instead, and route
 * clicks and long-running DOM waits through act() too, so whichever update
 * lands during the wait is captured.
 */
export async function pollWithinAct<TValue>(props: {
	readonly getValue: () => TValue;
	readonly isSatisfied: (value: TValue) => boolean;
	readonly pollIntervalMilliseconds?: number;
	readonly timeoutMilliseconds?: number;
}): Promise<TValue> {
	const timeoutMilliseconds = props.timeoutMilliseconds ?? 5000;
	const pollIntervalMilliseconds = props.pollIntervalMilliseconds ?? 20;
	const deadlineMilliseconds = Date.now() + timeoutMilliseconds;
	// oxlint-disable-next-line no-unreachable-loop -- Bounded poll loop with an early return per iteration.
	for (;;) {
		const value = props.getValue();
		if (props.isSatisfied(value) || Date.now() >= deadlineMilliseconds) {
			return value;
		}
		// oxlint-disable-next-line no-await-in-loop -- Real-time settling (ResizeObserver, rAF, intake round trips) must drain sequentially inside act().
		await act(async (): Promise<void> => {
			await new Promise<void>((resolve): void => {
				setTimeout(resolve, pollIntervalMilliseconds);
			});
		});
	}
}

export function pollWithinActUntilTruthy<TValue>(getValue: () => TValue): Promise<TValue> {
	return pollWithinAct({ getValue, isSatisfied: (value): boolean => Boolean(value) });
}

export function pollWithinActUntilEqual<TValue>(
	getValue: () => TValue,
	expectedValue: TValue,
): Promise<TValue> {
	return pollWithinAct({ getValue, isSatisfied: (value): boolean => value === expectedValue });
}

/** Wraps a click so any React updates it triggers are act()-protected. */
export function actClick(element: { readonly click: () => void }): Promise<void> {
	return act(async (): Promise<void> => {
		element.click();
		await Promise.resolve();
	});
}

/**
 * Wraps an arbitrary async DOM wait (for example one of the recursive
 * `waitForBridgeViewer*` polling helpers) in act(). React's act-scope
 * tracking is a global (`ReactSharedInternals.actQueue`), not lexically
 * scoped, so wrapping the call site here still protects updates that occur
 * inside the awaited helper's own internal polling loop.
 */
export function actWait<TValue>(wait: () => Promise<TValue>): Promise<TValue> {
	return act(wait);
}

/**
 * Wraps a single discrete, synchronous, state-mutating action (a
 * `document.dispatchEvent` call, a real-timer settle delay) plus one
 * microtask drain in act(). Use this for a single-shot action, not a
 * multi-tick poll — see `pollWithinAct`'s note for why those differ.
 */
export async function actUpdate(update: () => void): Promise<void> {
	await act(async (): Promise<void> => {
		update();
		await Promise.resolve();
	});
}

export function isBridgeTelemetryCommand(value: unknown): value is {
	readonly method: 'system.bridgeTelemetry';
	readonly params: {
		readonly samples: readonly {
			readonly name: string;
			readonly numericAttributes: Readonly<Record<string, number>>;
			readonly stringAttributes: Readonly<Record<string, string>>;
		}[];
	};
} {
	return (
		typeof value === 'object' &&
		value !== null &&
		'method' in value &&
		value.method === 'system.bridgeTelemetry' &&
		'params' in value &&
		typeof value.params === 'object' &&
		value.params !== null &&
		'samples' in value.params &&
		Array.isArray(value.params.samples)
	);
}

export function makeWindowedReviewPackage(itemCount: number): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const items = Array.from({ length: itemCount }, (_value, index) => {
		const itemIndex = String(index).padStart(3, '0');
		return makeBridgeReviewItem({
			itemId: `item-${itemIndex}`,
			path: `Sources/Windowed/File${itemIndex}.swift`,
		});
	});
	const itemsById: BridgeReviewPackage['itemsById'] = {};
	for (const item of items) {
		itemsById[item.itemId] = item;
	}
	return {
		...basePackage,
		orderedItemIds: items.map((item) => item.itemId),
		itemsById,
		summary: {
			...basePackage.summary,
			filesChanged: itemCount,
			visibleFileCount: itemCount,
			additions: itemCount,
			deletions: itemCount,
		},
	};
}

export function chunkedTextResponse(chunks: readonly string[]): Response {
	return new Response(
		new ReadableStream<Uint8Array>({
			start(controller): void {
				const encoder = new TextEncoder();
				for (const chunk of chunks) {
					controller.enqueue(encoder.encode(chunk));
				}
				controller.close();
			},
		}),
		{
			headers: {
				'content-type': 'text/plain; charset=utf-8',
			},
		},
	);
}

export function makeWorktreeFileSourceIdentityForFrameTest(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'file-frame-source',
		repoId: 'file-frame-repo',
		worktreeId: 'file-frame-worktree',
		subscriptionGeneration: 1,
		sourceCursor: 'file-frame-cursor',
	};
}

export function makeWorktreeFileDescriptorForFrameTest(): WorktreeFileDescriptor {
	const sourceIdentity = makeWorktreeFileSourceIdentityForFrameTest();
	return {
		path: 'Sources/App/StableAcrossModes.swift',
		fileId: 'file-frame-stable',
		contentHandle: 'file-frame-stable-content',
		contentDescriptor: {
			ref: {
				descriptorId: 'file-frame-stable-content',
				expectedProtocol: 'worktree-file',
				expectedResourceKind: 'worktree.fileContent',
				expectedIdentity: {
					paneId: 'bridge-worktree-dev-pane',
					protocol: 'worktree-file',
					sourceId: sourceIdentity.sourceId,
					generation: sourceIdentity.subscriptionGeneration,
					streamId: 'worktree-file:bridge-worktree-dev-pane',
					cursor: sourceIdentity.sourceCursor,
				},
			},
			descriptor: {
				descriptorId: 'file-frame-stable-content',
				protocol: 'worktree-file',
				resourceKind: 'worktree.fileContent',
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/file-frame-stable-content?generation=1&cursor=file-frame-cursor',
				identity: {
					paneId: 'bridge-worktree-dev-pane',
					protocol: 'worktree-file',
					sourceId: sourceIdentity.sourceId,
					generation: sourceIdentity.subscriptionGeneration,
					streamId: 'worktree-file:bridge-worktree-dev-pane',
					cursor: sourceIdentity.sourceCursor,
				},
				content: {
					mediaType: 'text/plain',
					encoding: 'utf-8',
					expectedBytes: 39,
					maxBytes: 39,
				},
			},
		},
		sourceIdentity,
		sizeBytes: 39,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
		language: 'swift',
		fileExtension: 'swift',
	};
}

export function makeWorktreeFileFramesForFrameTest(
	descriptor: WorktreeFileDescriptor,
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'snapshot',
			streamId: 'worktree-file:bridge-worktree-dev-pane',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: descriptor.sourceIdentity,
			metadataLineage: {
				loadedBy: 'startup_window',
				lane: 'foreground',
			},
			treeRows: [
				{
					rowId: 'row-stable-across-modes',
					path: descriptor.path,
					name: 'StableAcrossModes.swift',
					parentPath: 'Sources/App',
					depth: 2,
					isDirectory: false,
					fileId: descriptor.fileId,
				},
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 1,
				windowStartIndex: 0,
				windowRowCount: 1,
				rowHeightPixels: 24,
			},
		},
		{
			kind: 'delta',
			streamId: 'worktree-file:bridge-worktree-dev-pane',
			generation: 1,
			sequence: 1,
			frameKind: 'worktree.fileDescriptor',
			descriptor,
		},
	];
}
