import { createHash } from 'node:crypto';

import { vi } from 'vitest';

import type { BridgeTelemetrySample } from '../../../foundation/telemetry/bridge-telemetry-event.js';
import {
	BridgeCommWorkerAnnotationProjectionQueryController,
	type BridgeCommWorkerAnnotationProjectionPublication,
	type BridgeCommWorkerAnnotationProjectionTransport,
} from '../bridge-comm-worker-annotation-projection-query-controller.js';
import type { BridgeProductMetadataDataFrame } from '../bridge-product-metadata-application-protocol.js';
import {
	bridgeProductFileAnnotationMetadataApplicationProtocol,
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
} from '../bridge-product-metadata-application-registry.js';
import type {
	BridgeProductContentStream,
	BridgeProductMetadataApplicationSubscription,
} from '../bridge-product-transport-contract.js';
import type { BridgeProductWorktreeAnnotationEvent } from '../bridge-product-worktree-annotation-contracts.js';
import type {
	BridgeProductAnnotationProjectionContentDescriptor,
	BridgeProductAnnotationProjectionQueryRequest,
} from '../bridge-product-worktree-annotation-projection-query-contracts.js';

export const worktreeId = 'worktree-annotations-1';
export const sessionId = uuidv7(1);
const threadId = uuidv7(2);

export interface MutableProjectionPage {
	descriptor: BridgeProductAnnotationProjectionContentDescriptor;
	readonly bytes: Uint8Array<ArrayBuffer>;
}

export interface TestNotificationQueue {
	readonly close: () => void;
	readonly push: (event: BridgeProductWorktreeAnnotationEvent) => void;
	readonly subscription: AnnotationMetadataSubscription;
}

type AnnotationMetadataProtocol =
	| typeof bridgeProductFileAnnotationMetadataApplicationProtocol
	| typeof bridgeProductReviewAnnotationMetadataApplicationProtocol;
type AnnotationMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<AnnotationMetadataProtocol>;
type AnnotationMetadataFrame = BridgeProductMetadataDataFrame<BridgeProductWorktreeAnnotationEvent>;

export interface AnnotationProjectionTestHarness {
	readonly catalogAuthorityRetirements: boolean[];
	readonly controller: BridgeCommWorkerAnnotationProjectionQueryController;
	readonly failures: unknown[];
	readonly notifications: TestNotificationQueue;
	readonly publications: Array<{
		readonly contentSessionIds: readonly string[];
		readonly reviewPublicationIdentity?:
			| Extract<
					BridgeCommWorkerAnnotationProjectionPublication['state'],
					{ readonly kind: 'ready' }
			  >['reviewPublicationIdentity']
			| undefined;
		readonly snapshot: Extract<
			BridgeCommWorkerAnnotationProjectionPublication['state'],
			{ readonly kind: 'ready' }
		>['snapshot'];
		readonly surface: BridgeCommWorkerAnnotationProjectionPublication['surface'];
	}>;
	readonly querySourceGenerations: number[];
	readonly querySessionIds: string[][];
	readonly sourceAuthorityStalePublications: Array<{
		readonly currentSourceGeneration: number;
		readonly requestedSourceGeneration: number;
		readonly surface: 'file' | 'review';
	}>;
	readonly statuses: Array<BridgeCommWorkerAnnotationProjectionPublication['state']['kind']>;
	readonly subscriptionCount: () => number;
	readonly telemetrySamples: BridgeTelemetrySample[];
}

export async function createHarness(props: {
	readonly notificationQueues?: readonly TestNotificationQueue[];
	readonly pages: readonly MutableProjectionPage[];
	readonly queryOverride?: (
		request: BridgeProductAnnotationProjectionQueryRequest,
		signal: AbortSignal,
	) => Promise<unknown>;
	readonly terminalKind?: 'complete' | 'error';
	readonly surface?: 'file' | 'review';
}): Promise<AnnotationProjectionTestHarness> {
	const surface = props.surface ?? 'file';
	const notifications = createNotificationQueue(surface);
	const notificationQueues = props.notificationQueues ?? [notifications];
	let observedSubscriptionCount = 0;
	const publications: AnnotationProjectionTestHarness['publications'] = [];
	const failures: unknown[] = [];
	const catalogAuthorityRetirements: boolean[] = [];
	const statuses: AnnotationProjectionTestHarness['statuses'] = [];
	const querySourceGenerations: number[] = [];
	const querySessionIds: string[][] = [];
	const sourceAuthorityStalePublications: AnnotationProjectionTestHarness['sourceAuthorityStalePublications'] =
		[];
	const telemetrySamples: BridgeTelemetrySample[] = [];
	const pageByCursor = new Map<string | null, MutableProjectionPage>();
	for (const page of props.pages) {
		const cursor =
			page.descriptor.page.pageOrdinal === 0 ? null : `cursor-${page.descriptor.page.pageOrdinal}`;
		pageByCursor.set(cursor, page);
	}
	const transport: BridgeCommWorkerAnnotationProjectionTransport = {
		callProjection: async (_surface, request, signal): Promise<unknown> => {
			querySourceGenerations.push(request.sourceGeneration);
			querySessionIds.push([...request.sessionIds]);
			if (props.queryOverride !== undefined) return await props.queryOverride(request, signal);
			return { descriptor: pageByCursor.get(request.cursor)?.descriptor, kind: 'content' };
		},
		openContent: (descriptor): BridgeProductContentStream<'annotation.projection'> => {
			const page = props.pages.find(
				(candidate) => candidate.descriptor.descriptorId === descriptor.descriptorId,
			);
			if (page === undefined) throw new Error('Unknown annotation projection descriptor.');
			return makeContentStream(page, props.terminalKind ?? 'complete');
		},
		subscribe: () => {
			const subscription = notificationQueues[observedSubscriptionCount]?.subscription;
			observedSubscriptionCount += 1;
			if (subscription === undefined) throw new Error('Unexpected annotation subscription reopen.');
			return subscription;
		},
	};
	const controller = new BridgeCommWorkerAnnotationProjectionQueryController({
		onCatalog: (): void => {},
		onConvergence: ({ state, surface: publicationSurface }): void => {
			statuses.push(state.kind);
			if (state.kind === 'ready') {
				publications.push({
					contentSessionIds: state.contentSessionIds,
					...('reviewPublicationIdentity' in state
						? { reviewPublicationIdentity: state.reviewPublicationIdentity }
						: {}),
					snapshot: state.snapshot,
					surface: publicationSurface,
				});
			} else if (state.kind === 'unavailable') {
				failures.push(state.error);
				catalogAuthorityRetirements.push(state.catalogAuthorityRetired);
			}
		},
		onSourceAuthorityStale: (publication): void => {
			sourceAuthorityStalePublications.push(publication);
		},
		surface,
		telemetryClient: {
			record: (sample): void => {
				telemetrySamples.push(sample);
			},
		},
		transport,
	});
	return {
		catalogAuthorityRetirements,
		controller,
		failures,
		notifications,
		publications,
		querySourceGenerations,
		querySessionIds,
		sourceAuthorityStalePublications,
		statuses,
		subscriptionCount: (): number => observedSubscriptionCount,
		telemetrySamples,
	};
}

export function createNotificationQueue(surface: 'file' | 'review'): TestNotificationQueue {
	const pending: Array<IteratorResult<AnnotationMetadataFrame>> = [];
	const waiters: Array<(result: IteratorResult<AnnotationMetadataFrame>) => void> = [];
	const events: AsyncIterable<AnnotationMetadataFrame> = {
		[Symbol.asyncIterator]: () => ({
			next: async (): Promise<IteratorResult<AnnotationMetadataFrame>> => {
				const result = pending.shift();
				if (result !== undefined) return result;
				return await new Promise((resolve) => waiters.push(resolve));
			},
		}),
	};
	const base = {
		cancel: vi.fn(async (): Promise<void> => {
			for (const resolve of waiters.splice(0)) resolve({ done: true, value: undefined });
		}),
		events,
		update: vi.fn(async (): Promise<void> => {}),
	};
	const subscription: AnnotationMetadataSubscription =
		surface === 'file'
			? {
					...base,
					subscriptionId: 'file-annotation-notifications',
					subscriptionKind: 'file.annotations',
				}
			: {
					...base,
					subscriptionId: 'review-annotation-notifications',
					subscriptionKind: 'review.annotations',
				};
	return {
		close: (): void => {
			for (const resolve of waiters.splice(0)) resolve({ done: true, value: undefined });
			pending.push({ done: true, value: undefined });
		},
		push: (event: BridgeProductWorktreeAnnotationEvent): void => {
			const frame = annotationMetadataFrame(event, subscription);
			const resolve = waiters.shift();
			if (resolve === undefined) pending.push({ done: false, value: frame });
			else resolve({ done: false, value: frame });
		},
		subscription,
	};
}

export async function makeProjectionPages(
	messageCount: number,
	sourceGeneration: number,
	maximumPageBytes = 2 * 1024 * 1024,
	surface: 'file' | 'review' = 'file',
): Promise<MutableProjectionPage[]> {
	const records: Uint8Array<ArrayBuffer>[] = [];
	const header = {
		header: {
			expectedMessageCount: messageCount,
			expectedSessionCount: 1,
			expectedThreadCount: 1,
			projectionRevision: sourceGeneration,
			recoveryStatus: 'available',
			sessions: [
				{
					completedAtUnixMilliseconds: null,
					createdAtUnixMilliseconds: 1,
					eligibleMessageCount: messageCount,
					eligibleWithoutInlinePlacementCount: 0,
					lifecycle: 'living',
					semanticRevision: sourceGeneration,
					sessionId,
					sourceRelationship: 'applicable',
					updatedAtUnixMilliseconds: 2,
				},
			],
			sourceGeneration,
			worktreeId,
		},
		kind: 'header',
	};
	records.push(encodeRecord(header));
	for (let ordinal = 0; ordinal < messageCount; ordinal += 1) {
		records.push(
			encodeRecord({
				kind: 'message',
				message: {
					context: {
						diffSide: 'additions',
						endLine: 12,
						path: 'Sources/App.swift',
						placement: 'exact',
						resolution: 'open',
						scope: 'located',
						sourceIdentity: 'source-1',
						sourceRole: 'file',
						startLine: 10,
						threadId,
					},
					message: {
						attentionState: 'not_applicable',
						authorKind: 'human',
						createdAtUnixMilliseconds: ordinal + 3,
						draft: null,
						handled: false,
						messageId: uuidv7(ordinal + 100),
						messageRevision: 1,
						ordinal,
						savedBody: messageCount > 100 ? 'x'.repeat(16_000) : `message-${ordinal}`,
						savedRevision: 1,
						sessionId,
						sessionRevision: sourceGeneration,
						status: 'locked',
						threadId,
						threadRevision: 1,
					},
				},
			}),
		);
	}
	const pageRecords: Uint8Array<ArrayBuffer>[][] = [[]];
	let currentPageBytes = 0;
	for (const record of records) {
		if (currentPageBytes > 0 && currentPageBytes + record.byteLength > maximumPageBytes) {
			pageRecords.push([]);
			currentPageBytes = 0;
		}
		pageRecords.at(-1)?.push(record);
		currentPageBytes += record.byteLength;
	}
	const pages = pageRecords.map((page) => concatenate(page));
	const aggregateSha256 = createHash('sha256').update(concatenate(pages)).digest('hex');
	return pages.map((bytes, pageOrdinal) => ({
		bytes,
		descriptor: {
			contentKind: 'annotation.projection',
			descriptorId: `projection-${sourceGeneration}-${pageOrdinal}`,
			maximumBytes: bytes.byteLength,
			page: {
				aggregateSha256,
				expectedMessageCount: messageCount,
				expectedPageCount: pages.length,
				expectedSessionCount: 1,
				expectedThreadCount: 1,
				isLastPage: pageOrdinal === pages.length - 1,
				nextCursor: pageOrdinal === pages.length - 1 ? null : `cursor-${pageOrdinal + 1}`,
				operationCorrelationId: 'a'.repeat(64),
				pageOrdinal,
				projectionRevision: sourceGeneration,
				snapshotId: uuidv7(sourceGeneration + 10_000),
				sourceGeneration,
			},
			surface,
		},
	}));
}

function makeContentStream(
	page: MutableProjectionPage,
	terminalKind: 'complete' | 'error',
): BridgeProductContentStream<'annotation.projection'> {
	return {
		contentKind: 'annotation.projection',
		contentRequestId: `request-${page.descriptor.descriptorId}`,
		frames: { async *[Symbol.asyncIterator]() {} },
		terminal:
			terminalKind === 'complete'
				? Promise.resolve({
						bytes: page.bytes.buffer,
						contentKind: 'annotation.projection',
						descriptorId: page.descriptor.descriptorId,
						endOfSource: true,
						kind: 'complete',
						observedByteLength: page.bytes.byteLength,
						observedSha256: createHash('sha256').update(page.bytes).digest('hex'),
					})
				: Promise.resolve({
						code: 'internal',
						contentKind: 'annotation.projection',
						descriptorId: page.descriptor.descriptorId,
						kind: 'error',
						retryable: true,
						safeMessage: 'projection unavailable',
					}),
	};
}

function encodeRecord(record: unknown): Uint8Array<ArrayBuffer> {
	return new TextEncoder().encode(`${JSON.stringify(record)}\n`);
}

function concatenate(chunks: readonly Uint8Array<ArrayBuffer>[]): Uint8Array<ArrayBuffer> {
	const result = new Uint8Array(chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0));
	let offset = 0;
	for (const chunk of chunks) {
		result.set(chunk, offset);
		offset += chunk.byteLength;
	}
	return result;
}

export function controlChanged(sourceGeneration: number): BridgeProductWorktreeAnnotationEvent {
	return {
		authority: {
			applicationSourceGeneration: sourceGeneration,
			worktreeId,
		},
		kind: 'annotation.controlChanged',
		reason: 'discovery',
	};
}

export function sessionChanged(
	sourceGeneration: number,
	semanticRevision: number,
): BridgeProductWorktreeAnnotationEvent {
	return {
		authority: {
			applicationSourceGeneration: sourceGeneration,
			worktreeId,
		},
		kind: 'annotation.sessionChanged',
		semanticRevision,
		sessionId,
	};
}

export function pushSessionCatalog(
	notifications: TestNotificationQueue,
	sourceGeneration: number,
): void {
	const transferId = `catalog-transfer-${sourceGeneration}`;
	const authority = {
		applicationSourceGeneration: sourceGeneration,
		worktreeId,
	} as const;
	notifications.push({
		authority,
		kind: 'annotation.catalog',
		transfer: {
			catalogRevision: sourceGeneration,
			expectedEntryCount: 1,
			kind: 'catalog.begin',
			transferId,
		},
	});
	notifications.push({
		authority,
		kind: 'annotation.catalog',
		transfer: {
			catalogRevision: sourceGeneration,
			entries: [{ kind: 'session', semanticRevision: 1, sessionId }],
			kind: 'catalog.window',
			transferId,
			windowOrdinal: 0,
		},
	});
	notifications.push({
		authority,
		kind: 'annotation.catalog',
		transfer: {
			catalogRevision: sourceGeneration,
			entryCount: 1,
			kind: 'catalog.commit',
			transferId,
			windowCount: 1,
		},
	});
}

function annotationMetadataFrame(
	event: BridgeProductWorktreeAnnotationEvent,
	subscription: AnnotationMetadataSubscription,
): AnnotationMetadataFrame {
	return {
		data: event,
		metadataStreamId: 'annotation-metadata-stream',
		operationCorrelationId: 'a'.repeat(64),
		sourceGeneration: event.authority.applicationSourceGeneration,
		streamSequence: 1,
		subscriptionId: subscription.subscriptionId,
		subscriptionKind: subscription.subscriptionKind,
		subscriptionSequence: 1,
		workerDerivationEpoch: 1,
	};
}

export function uuidv7(value: number): string {
	return `00000000-0000-7000-8000-${value.toString().padStart(12, '0')}`;
}

export function deferred<TResult>(): {
	readonly promise: Promise<TResult>;
	readonly resolve: (value: TResult) => void;
} {
	let resolvePromise!: (value: TResult) => void;
	const promise = new Promise<TResult>((resolve): void => {
		resolvePromise = resolve;
	});
	return { promise, resolve: resolvePromise };
}

export async function flushMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
}

export async function flushTaskQueue(): Promise<void> {
	await new Promise<void>((resolve): void => {
		const channel = new MessageChannel();
		channel.port1.addEventListener(
			'message',
			(): void => {
				channel.port1.close();
				channel.port2.close();
				resolve();
			},
			{ once: true },
		);
		channel.port1.start();
		channel.port2.postMessage(null);
	});
}

export async function flushTaskQueueUntil(predicate: () => boolean): Promise<void> {
	for (let turn = 0; turn < 10; turn += 1) {
		if (predicate()) return;
		// eslint-disable-next-line no-await-in-loop -- Each turn waits for the exact queued task boundary.
		await flushTaskQueue();
	}
	throw new Error('Expected queued annotation projection work to reach its boundary.');
}
