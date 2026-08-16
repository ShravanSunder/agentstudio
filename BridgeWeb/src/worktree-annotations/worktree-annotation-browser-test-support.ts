import { createElement, type ReactElement, type ReactNode } from 'react';

import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeProductWorktreeAnnotationEvent } from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationOutputHistorySummary,
	WorktreeAnnotationThreadContext,
} from './worktree-annotation-surface-client.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';

export const annotationSessionId = '00000000-0000-7000-8000-000000000011';
export const annotationSecondSessionId = '00000000-0000-7000-8000-000000000014';
export const annotationHeadThreadId = '00000000-0000-7000-8000-000000000012';
export const annotationBaseThreadId = '00000000-0000-7000-8000-000000000013';

export interface WorktreeAnnotationBrowserProviderHarness {
	readonly surface: RecordingAnnotationBrowserSurface;
	readonly wrap: (children: ReactNode) => ReactElement;
}

export function createWorktreeAnnotationBrowserProviderHarness(
	surfaceKind: 'fileView' | 'review',
): WorktreeAnnotationBrowserProviderHarness {
	const surface = new RecordingAnnotationBrowserSurface(surfaceKind);
	return {
		surface,
		wrap: (children): ReactElement =>
			createElement(WorktreeAnnotationSurfaceProvider, {
				// oxlint-disable-next-line react/no-children-prop -- This shared test helper is a .ts module without JSX.
				children,
				surfaceClient: surface.client,
			}),
	};
}

type AnnotationCommandOutcome = Extract<
	BridgeProductWorktreeAnnotationEvent,
	{ readonly eventKind: 'projection.state' }
>['payload']['commandOutcomes'][number];
export type AnnotationSessionSummary = Extract<
	BridgeProductWorktreeAnnotationEvent,
	{ readonly eventKind: 'projection.state' }
>['payload']['sessions'][number];
type AnnotationOutputCommandOutcome = Extract<
	AnnotationCommandOutcome['status'],
	{ readonly kind: 'output' }
>['outcome'];

export class RecordingAnnotationBrowserSurface {
	readonly #listeners = new Set<(message: BridgeWorkerServerToMainMessage) => void>();
	readonly client: BridgePaneSurfaceClient;
	readonly sentOperations: BridgeProductWorktreeAnnotationOperation[] = [];
	readonly sentOutputInspectionAttemptIds: string[] = [];
	#lastOutputInspectionRequestId: string | null = null;
	#nextRequest = 0;
	#outputHistory: readonly WorktreeAnnotationOutputHistorySummary[] = [];
	#revision = 0;
	#sessions: Extract<
		BridgeProductWorktreeAnnotationEvent,
		{ readonly eventKind: 'projection.state' }
	>['payload']['sessions'] = [];
	readonly #threadsById = new Map<
		string,
		{
			readonly context: WorktreeAnnotationThreadContext;
			readonly message: WorktreeAnnotationMessageEntry;
		}
	>();

	constructor(
		surface: 'fileView' | 'review',
		props: { readonly failRootCreateWithConflict?: boolean } = {},
	) {
		const renderStore = createBridgeMainRenderSnapshotStore();
		this.client = {
			lifecycle: {
				getServerSnapshot: () => ({ requestsById: {} }),
				getSnapshot: () => ({ requestsById: {} }),
				subscribe: () => (): void => {},
			},
			renderFulfillmentCoordinator: {} as BridgePaneSurfaceClient['renderFulfillmentCoordinator'],
			renderStore,
			send: (command): string => {
				if (
					command.command !== 'annotationCommand' &&
					command.command !== 'annotationOutputInspect'
				) {
					throw new Error(`Unexpected browser annotation command ${command.command}.`);
				}
				this.#nextRequest += 1;
				const requestId = `worker-request-${this.#nextRequest}`;
				if (command.command === 'annotationOutputInspect') {
					this.sentOutputInspectionAttemptIds.push(command.attemptId);
					this.#lastOutputInspectionRequestId = requestId;
					return requestId;
				}
				this.sentOperations.push(command.operation);
				if (props.failRootCreateWithConflict === true && command.operation.kind === 'root.create') {
					queueMicrotask((): void => this.#publishConflict(requestId));
				}
				return requestId;
			},
			subscribeMessages: (listener): (() => void) => {
				this.#listeners.add(listener);
				return (): void => {
					this.#listeners.delete(listener);
				};
			},
			surface,
		};
	}

	publishProjection(revision: number): void {
		this.publishProjectionState({
			revision,
			sessions: [
				{
					completedAt: null,
					createdAt: 1,
					lifecycle: 'living',
					semanticRevision: revision,
					sessionId: annotationSessionId,
					sourceRelationship: 'applicable',
					updatedAt: revision,
				},
			],
		});
	}

	publishProjectionState(props: {
		readonly commandOutcomes?: readonly AnnotationCommandOutcome[];
		readonly outputHistory?: readonly WorktreeAnnotationOutputHistorySummary[];
		readonly recoveryStatus?: 'available' | 'recovered_degraded' | 'unavailable';
		readonly revision: number;
		readonly sessions: readonly AnnotationSessionSummary[];
	}): void {
		this.#revision = props.revision;
		this.#sessions = props.sessions;
		this.#outputHistory = props.outputHistory ?? [];
		this.#publishAnnotationEvent({
			eventKind: 'projection.state',
			payload: {
				commandOutcomes: props.commandOutcomes ?? [],
				outputHistory: this.#outputHistory,
				recoveryStatus: props.recoveryStatus ?? 'available',
				revision: props.revision,
				sessions: this.#sessions,
				worktreeId: 'worktree-1',
			},
		});
	}

	publishThread(props: {
		readonly context: WorktreeAnnotationThreadContext;
		readonly message: WorktreeAnnotationMessageEntry;
	}): void {
		this.#threadsById.set(props.context.threadId, props);
		this.#publishThreadEvent(props);
	}

	settleMostRecentOutput(outcome: AnnotationOutputCommandOutcome): void {
		if (this.#nextRequest === 0) throw new Error('No annotation output command is pending.');
		const workerRequestId = `worker-request-${this.#nextRequest}`;
		const productRequestId = `product-${workerRequestId}`;
		this.#publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationCommandAccepted',
			productRequestId,
			requestId: workerRequestId,
			surface: this.client.surface,
			transferDescriptors: [],
			wireVersion: 1,
		});
		this.#revision += 1;
		this.publishProjectionState({
			commandOutcomes: [
				{
					requestId: productRequestId,
					sessionId: annotationSessionId,
					status: { kind: 'output', outcome },
					surface: this.client.surface === 'fileView' ? 'file' : 'review',
				},
			],
			outputHistory: this.#outputHistory,
			revision: this.#revision,
			sessions: this.#sessions,
		});
		for (const thread of this.#threadsById.values()) this.#publishThreadEvent(thread);
	}

	settleMostRecentInspection(props: {
		readonly attemptId: string;
		readonly content: string;
		readonly outputKind: 'clipboard_markdown' | 'json_file';
	}): void {
		if (this.#lastOutputInspectionRequestId === null) {
			throw new Error('No annotation output inspection is pending.');
		}
		const exactBytes = new TextEncoder().encode(props.content);
		const exactBuffer = exactBytes.buffer.slice(
			exactBytes.byteOffset,
			exactBytes.byteOffset + exactBytes.byteLength,
		) as ArrayBuffer;
		const descriptorBase = {
			attemptId: props.attemptId,
			contentKind: 'annotation.output' as const,
			declaredByteLength: exactBytes.byteLength,
			descriptorId: `annotation-output-${props.attemptId}`,
			encoding: 'utf-8' as const,
			expectedSha256: 'a'.repeat(64),
			formatVersion: 1 as const,
			maximumBytes: exactBytes.byteLength,
			surface: this.client.surface === 'fileView' ? ('file' as const) : ('review' as const),
		};
		const descriptor =
			props.outputKind === 'clipboard_markdown'
				? {
						...descriptorBase,
						contentType: 'text/markdown; charset=utf-8' as const,
						outputKind: 'clipboard_markdown' as const,
					}
				: {
						...descriptorBase,
						contentType: 'application/json; charset=utf-8' as const,
						outputKind: 'json_file' as const,
					};
		this.#publish({
			descriptor,
			direction: 'serverWorkerToMain',
			exactBytes: exactBuffer,
			kind: 'annotationOutputInspection',
			requestId: this.#lastOutputInspectionRequestId,
			surface: this.client.surface,
			transferDescriptors: [
				{
					byteLength: exactBytes.byteLength,
					fieldPath: ['exactBytes'],
					messageKind: 'annotationOutputInspection',
					mode: 'transfer',
				},
			],
			wireVersion: 1,
		});
		this.#lastOutputInspectionRequestId = null;
	}

	#publishThreadEvent(props: {
		readonly context: WorktreeAnnotationThreadContext;
		readonly message: WorktreeAnnotationMessageEntry;
	}): void {
		this.#publishAnnotationEvent({
			eventKind: 'message.batch',
			payload: {
				context: props.context,
				isLastBatchForThread: true,
				messages: [props.message],
				revision: this.#revision,
			},
		});
	}

	#publishConflict(workerRequestId: string): void {
		const productRequestId = `product-${workerRequestId}`;
		this.#publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationCommandAccepted',
			productRequestId,
			requestId: workerRequestId,
			surface: this.client.surface,
			transferDescriptors: [],
			wireVersion: 1,
		});
		const outcome = {
			requestId: productRequestId,
			sessionId: annotationSessionId,
			status: { code: 'conflict', kind: 'failed' },
			surface: this.client.surface === 'fileView' ? 'file' : 'review',
		} satisfies AnnotationCommandOutcome;
		this.#revision += 1;
		this.#publishAnnotationEvent({
			eventKind: 'projection.state',
			payload: {
				commandOutcomes: [outcome],
				outputHistory: [],
				recoveryStatus: 'available',
				revision: this.#revision,
				sessions: this.#sessions,
				worktreeId: 'worktree-1',
			},
		});
	}

	#publishAnnotationEvent(event: BridgeProductWorktreeAnnotationEvent): void {
		this.#publish({
			direction: 'serverWorkerToMain',
			event,
			kind: 'annotationProjection',
			surface: this.client.surface,
			transferDescriptors: [],
			wireVersion: 1,
		});
	}

	#publish(message: BridgeWorkerServerToMainMessage): void {
		for (const listener of this.#listeners) listener(message);
	}
}

export function annotationSessionSummary(props: {
	readonly lifecycle?: 'completed' | 'living';
	readonly revision: number;
	readonly sessionId: string;
	readonly sourceRelationship?: 'applicable' | 'detached' | 'uncertain';
}): AnnotationSessionSummary {
	return {
		completedAt: props.lifecycle === 'completed' ? props.revision : null,
		createdAt: props.revision,
		lifecycle: props.lifecycle ?? 'living',
		semanticRevision: props.revision,
		sessionId: props.sessionId,
		sourceRelationship: props.sourceRelationship ?? 'applicable',
		updatedAt: props.revision,
	};
}

export function annotationMessage(props: {
	readonly messageId: string;
	readonly ordinal?: number;
	readonly sessionRevision?: number;
	readonly threadId: string;
}): WorktreeAnnotationMessageEntry {
	return {
		authorKind: 'human',
		createdAt: props.ordinal ?? 0,
		draft: null,
		messageId: props.messageId,
		messageRevision: 1,
		ordinal: props.ordinal ?? 0,
		savedBody: `## Comment ${props.messageId.at(-1)}`,
		savedRevision: 1,
		sessionId: annotationSessionId,
		sessionRevision: props.sessionRevision ?? 1,
		status: 'editable',
		threadId: props.threadId,
	};
}
