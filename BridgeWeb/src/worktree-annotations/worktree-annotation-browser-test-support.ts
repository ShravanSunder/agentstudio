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
const annotationSubscriptionId = 'annotation-browser-subscription-1';

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
	readonly sentOutputCandidateQueries: Array<{
		readonly cursor:
			| { readonly kind: 'start' }
			| { readonly flatOrdinal: number; readonly kind: 'after'; readonly messageId: string };
		readonly expectedSessionRevision: number;
		readonly limit: number;
		readonly sessionId: string;
	}> = [];
	readonly sentOutputInspectionAttemptIds: string[] = [];
	readonly sentProjectionResyncs: Array<{
		readonly failureClass: string;
		readonly revision: number;
		readonly subscriptionId: string;
		readonly workerRequestId: string;
	}> = [];
	#lastOutputInspectionRequestId: string | null = null;
	#candidateQueryCount = 0;
	readonly #candidateQueryFailureCalls: ReadonlySet<number>;
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
			readonly messages: readonly WorktreeAnnotationMessageEntry[];
		}
	>();

	constructor(
		surface: 'fileView' | 'review',
		props: {
			readonly candidateQueryFailureCalls?: readonly number[];
			readonly failRootCreateWithConflict?: boolean;
		} = {},
	) {
		this.#candidateQueryFailureCalls = new Set(props.candidateQueryFailureCalls ?? []);
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
					command.command !== 'annotationOutputCandidatesQuery' &&
					command.command !== 'annotationOutputInspect' &&
					command.command !== 'annotationProjectionResync'
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
				if (command.command === 'annotationOutputCandidatesQuery') {
					this.sentOutputCandidateQueries.push(command.query);
					this.#candidateQueryCount += 1;
					if (this.#candidateQueryFailureCalls.has(this.#candidateQueryCount)) {
						queueMicrotask((): void => this.publishHealth(requestId, 'degraded'));
					} else {
						queueMicrotask((): void => this.#publishCandidatePage(requestId, command.query));
					}
					return requestId;
				}
				if (command.command === 'annotationProjectionResync') {
					this.sentProjectionResyncs.push({
						failureClass: command.failureClass,
						revision: command.revision,
						subscriptionId: command.subscriptionId,
						workerRequestId: requestId,
					});
					return requestId;
				}
				this.sentOperations.push(command.operation);
				const operation = command.operation;
				if (
					operation.kind === 'output.selection.begin' ||
					operation.kind === 'output.selection.chunk' ||
					operation.kind === 'output.selection.cancel'
				) {
					const sessionId = operation.sessionId;
					queueMicrotask((): void =>
						this.#publishCommandStatus(requestId, { kind: 'committed' }, sessionId),
					);
				}
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

	publishProjection(revision: number, expectedThreadCount: number): void {
		this.publishProjectionState({
			expectedThreadCount,
			revision,
			sessions: [
				{
					completedAt: null,
					createdAt: 1,
					eligibleMessageCount: 0,
					eligibleWithoutInlinePlacementCount: 0,
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
		readonly expectedThreadCount: number;
		readonly outputHistory?: readonly WorktreeAnnotationOutputHistorySummary[];
		readonly recoveryStatus?: 'available' | 'recovered_degraded' | 'unavailable';
		readonly revision: number;
		readonly sessions: readonly AnnotationSessionSummary[];
		readonly subscriptionId?: string;
	}): void {
		this.#revision = props.revision;
		this.#sessions = props.sessions;
		this.#outputHistory = props.outputHistory ?? [];
		this.#publishAnnotationEvent(
			{
				eventKind: 'projection.state',
				payload: {
					commandOutcomes: props.commandOutcomes ?? [],
					expectedThreadCount: props.expectedThreadCount,
					outputHistory: this.#outputHistory,
					recoveryStatus: props.recoveryStatus ?? 'available',
					revision: props.revision,
					sessions: this.#sessions,
					worktreeId: 'worktree-1',
				},
			},
			props.subscriptionId,
		);
	}

	publishThread(props: {
		readonly context: WorktreeAnnotationThreadContext;
		readonly message: WorktreeAnnotationMessageEntry;
	}): void {
		const thread = { context: props.context, messages: [props.message] };
		this.#threadsById.set(props.context.threadId, thread);
		this.#publishThreadEvent(thread);
	}

	publishThreadMessages(props: {
		readonly context: WorktreeAnnotationThreadContext;
		readonly messages: readonly WorktreeAnnotationMessageEntry[];
		readonly subscriptionId?: string;
	}): void {
		this.#threadsById.set(props.context.threadId, props);
		this.#publishThreadEvent(props, props.subscriptionId);
	}

	publishAnnotationEvent(
		event: BridgeProductWorktreeAnnotationEvent,
		subscriptionId: string,
	): void {
		this.#publishAnnotationEvent(event, subscriptionId);
	}

	publishHealth(requestId: string, status: 'degraded' | 'ready'): void {
		this.#publish({
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId,
			status,
			transferDescriptors: [],
			wireVersion: 1,
		});
	}

	settleMostRecentCommitted(
		sessionId: string = annotationSessionId,
		expectedThreadCount: number = this.#threadsById.size,
	): void {
		if (this.#nextRequest === 0) throw new Error('No annotation command is pending.');
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
					sessionId,
					status: { kind: 'committed' },
					surface: this.client.surface === 'fileView' ? 'file' : 'review',
				},
			],
			expectedThreadCount,
			outputHistory: this.#outputHistory,
			revision: this.#revision,
			sessions: this.#sessions,
		});
	}

	settleMostRecentAdmissionRequired(props: {
		readonly candidateSessionIds: readonly string[];
		readonly reason: 'applicable_session_choice' | 'uncertain_continuity_choice';
	}): void {
		if (this.#nextRequest === 0) throw new Error('No annotation command is pending.');
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
					sessionId: null,
					status: {
						candidateSessionIds: [...props.candidateSessionIds],
						kind: 'admission_required',
						reason: props.reason,
					},
					surface: this.client.surface === 'fileView' ? 'file' : 'review',
				},
			],
			expectedThreadCount: this.#threadsById.size,
			outputHistory: this.#outputHistory,
			revision: this.#revision,
			sessions: this.#sessions,
		});
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
			expectedThreadCount: this.#threadsById.size,
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

	#publishThreadEvent(
		props: {
			readonly context: WorktreeAnnotationThreadContext;
			readonly messages: readonly WorktreeAnnotationMessageEntry[];
		},
		subscriptionId?: string,
	): void {
		this.#publishAnnotationEvent(
			{
				eventKind: 'message.batch',
				payload: {
					context: props.context,
					isLastBatchForThread: true,
					messages: props.messages,
					revision: this.#revision,
				},
			},
			subscriptionId,
		);
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
				expectedThreadCount: this.#threadsById.size,
				outputHistory: [],
				recoveryStatus: 'available',
				revision: this.#revision,
				sessions: this.#sessions,
				worktreeId: 'worktree-1',
			},
		});
	}

	#publishCandidatePage(
		workerRequestId: string,
		operation: RecordingAnnotationBrowserSurface['sentOutputCandidateQueries'][number],
	): void {
		const allCandidates = [...this.#threadsById.values()]
			.flatMap((thread) =>
				thread.messages
					.filter(
						(message): boolean =>
							message.sessionId === operation.sessionId &&
							message.savedBody !== null &&
							message.savedRevision !== null &&
							message.draft === null &&
							message.status === 'editable',
					)
					.map((message) => ({ context: thread.context, message })),
			)
			.toSorted((left, right) => {
				if (left.context.path !== right.context.path) {
					return left.context.path.localeCompare(right.context.path);
				}
				if (left.context.startLine !== right.context.startLine) {
					return left.context.startLine - right.context.startLine;
				}
				return left.message.messageId.localeCompare(right.message.messageId);
			});
		const startIndex = operation.cursor.kind === 'start' ? 0 : operation.cursor.flatOrdinal + 1;
		const pageEntries = allCandidates.slice(startIndex, startIndex + operation.limit);
		const candidates = pageEntries.map(({ context, message }, index) => ({
			authoredAt: message.createdAt,
			endLine: context.endLine,
			excerpt:
				message.savedBody
					?.replaceAll(/[#*_`>|[\]()~-]/g, '')
					.trim()
					.slice(0, 240) ?? '',
			flatOrdinal: startIndex + index,
			location:
				context.placement === 'exact' || context.placement === 'relocated'
					? ('current' as const)
					: ('original' as const),
			messageId: message.messageId,
			path: context.path,
			placement: context.placement,
			startLine: context.startLine,
			state: 'eligible' as const,
			threadId: context.threadId,
		}));
		const lastCandidate = candidates.at(-1);
		this.#publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationOutputCandidatesPage',
			page: {
				candidates,
				eligibleMessageCount: allCandidates.length,
				eligibleWithoutInlinePlacementCount: allCandidates.filter(
					({ context }): boolean =>
						context.placement !== 'exact' && context.placement !== 'relocated',
				).length,
				nextCursor:
					startIndex + candidates.length < allCandidates.length && lastCandidate !== undefined
						? {
								flatOrdinal: lastCandidate.flatOrdinal,
								kind: 'after',
								messageId: lastCandidate.messageId,
							}
						: null,
				sessionId: operation.sessionId,
				sessionRevision: operation.expectedSessionRevision,
			},
			requestId: workerRequestId,
			surface: this.client.surface,
			transferDescriptors: [],
			wireVersion: 1,
		});
	}

	#publishCommandStatus(
		workerRequestId: string,
		status: AnnotationCommandOutcome['status'],
		sessionId: string | null,
	): void {
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
					sessionId,
					status,
					surface: this.client.surface === 'fileView' ? 'file' : 'review',
				},
			],
			expectedThreadCount: this.#threadsById.size,
			outputHistory: this.#outputHistory,
			revision: this.#revision,
			sessions: this.#sessions,
		});
		for (const thread of this.#threadsById.values()) this.#publishThreadEvent(thread);
	}

	#publishAnnotationEvent(
		event: BridgeProductWorktreeAnnotationEvent,
		subscriptionId: string = annotationSubscriptionId,
	): void {
		this.#publish({
			direction: 'serverWorkerToMain',
			event,
			kind: 'annotationProjection',
			subscriptionId,
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
	readonly eligibleMessageCount?: number;
	readonly eligibleWithoutInlinePlacementCount?: number;
	readonly lifecycle?: 'completed' | 'living';
	readonly revision: number;
	readonly sessionId: string;
	readonly sourceRelationship?: 'applicable' | 'detached' | 'uncertain';
}): AnnotationSessionSummary {
	return {
		completedAt: props.lifecycle === 'completed' ? props.revision : null,
		createdAt: props.revision,
		eligibleMessageCount: props.eligibleMessageCount ?? 0,
		eligibleWithoutInlinePlacementCount: props.eligibleWithoutInlinePlacementCount ?? 0,
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
