import { expect, vi } from 'vitest';

import type { BridgeAttachedResourceDescriptor } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	type BridgeAppNativeWorktreeFileBackend,
	createBridgeAppNativeWorktreeFileBackend,
} from './bridge-app-native-worktree-file.js';

export function cleanupNativeWorktreeFileBackendBrowserTest(): void {
	vi.useRealTimers();
	document.documentElement.removeAttribute('data-bridge-worktree-file-source-spec');
	document.body.replaceChildren();
	delete window.__bridgeNativeWorktreeFileProbe;
}

export interface NativeWorktreeFileRPCFetchHarness {
	readonly commandDetails: unknown[];
	readonly fetch: typeof fetch;
}

export interface NativeWorktreeFileRPCFetchHarnessOptions {
	readonly openSourceStreamResponse?: (command: unknown) => unknown;
	readonly requestFileDescriptorResponse?: (command: unknown) => unknown;
}

export function createNativeWorktreeFileRPCFetchHarness(
	options: NativeWorktreeFileRPCFetchHarnessOptions = {},
): NativeWorktreeFileRPCFetchHarness {
	const commandDetails: unknown[] = [];
	return {
		commandDetails,
		fetch: (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
			expect(input).toBe('agentstudio://rpc/command');
			expect(init?.method).toBe('POST');
			const command = decodeNativeWorktreeFileRPCCommand(init);
			commandDetails.push(command);
			const requestId = rpcRequestId(command);
			const method = rpcMethod(command);
			if (method === 'worktreeFileSurface.openSourceStream') {
				return Promise.resolve(
					Response.json(
						options.openSourceStreamResponse?.(command) ?? {
							id: requestId,
							result: makeOpenSourceOutcome(),
						},
					),
				);
			}
			if (method === 'worktreeFileSurface.requestFileDescriptor') {
				return Promise.resolve(
					Response.json(
						options.requestFileDescriptorResponse?.(command) ?? {
							id: requestId,
							result: {},
						},
					),
				);
			}
			return Promise.resolve(Response.json({ id: requestId, result: {} }));
		},
	};
}

export function makeSourceIdentity(
	props: { readonly subscriptionGeneration?: number; readonly sourceCursor?: string } = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: '11111111-1111-4111-8111-111111111111',
		worktreeId: '22222222-2222-4222-8222-222222222222',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-1',
		rootRevisionToken: 'root-token',
	};
}

export async function installReadyNativeWorktreeFileBackend(
	options: NativeWorktreeFileRPCFetchHarnessOptions = {},
): Promise<{
	readonly backend: BridgeAppNativeWorktreeFileBackend;
	readonly commandDetails: unknown[];
}> {
	const rpcFetch = createNativeWorktreeFileRPCFetchHarness(options);
	document.documentElement.setAttribute(
		'data-bridge-worktree-file-source-spec',
		JSON.stringify({
			clientRequestId: 'bootstrap-request',
			repoId: '11111111-1111-4111-8111-111111111111',
			worktreeId: '22222222-2222-4222-8222-222222222222',
			rootPathToken: 'root-token',
			includeStatuses: true,
			includeComments: false,
			includeAgentComms: false,
			freshness: 'live',
		}),
	);
	const backend = createBridgeAppNativeWorktreeFileBackend({
		createRequestId: (() => {
			let sequence = 0;
			return (): string => {
				sequence += 1;
				return `request-${sequence}`;
			};
		})(),
		fetchRPC: rpcFetch.fetch,
		target: document,
	});
	if (backend === null) {
		throw new Error('expected native worktree backend');
	}

	document.dispatchEvent(
		new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
	);
	const surfacePromise = backend.loadWorktreeFileSurface();
	await expect
		.poll(() => rpcFetch.commandDetails[1])
		.toMatchObject({
			method: 'bridge.intakeReady',
		});
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
		}),
	);
	await expect(surfacePromise).resolves.toMatchObject({
		source: makeSourceIdentity(),
	});
	return { backend, commandDetails: rpcFetch.commandDetails };
}

export function makeSnapshotFrame(
	props: {
		readonly generation?: number;
		readonly sequence?: number;
		readonly source?: WorktreeFileSurfaceSourceIdentity;
	} = {},
): Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }> {
	const generation = props.generation ?? 1;
	return {
		kind: 'snapshot',
		frameKind: 'worktree.snapshot',
		streamId: 'worktree-file:pane-1',
		generation,
		sequence: props.sequence ?? 0,
		source:
			props.source ??
			makeSourceIdentity({
				subscriptionGeneration: generation,
				sourceCursor: `cursor-${generation}`,
			}),
		metadataLineage: {
			loadedBy: 'startup_window',
			lane: 'foreground',
		},
		treeRows: [
			{
				rowId: 'row-1',
				path: 'Sources/App/View.swift',
				name: 'View.swift',
				parentPath: 'Sources/App',
				depth: 2,
				isDirectory: false,
				fileId: 'file-1',
			},
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: 1,
			rowHeightPixels: 24,
		},
	};
}

export function makeOpenSourceOutcome(): {
	readonly status: 'accepted';
	readonly protocol: 'worktree-file';
	readonly streamId: string;
	readonly generation: number;
} {
	return {
		status: 'accepted',
		protocol: 'worktree-file',
		streamId: 'worktree-file:pane-1',
		generation: 1,
	};
}

export function commandIdFromUnknownCommand(command: unknown): string {
	if (
		typeof command !== 'object' ||
		command === null ||
		!('id' in command) ||
		typeof command.id !== 'string'
	) {
		throw new Error('expected command with string id');
	}
	return command.id;
}

function decodeNativeWorktreeFileRPCCommand(init: RequestInit | undefined): unknown {
	const body = init?.body;
	if (typeof body !== 'string') {
		throw new Error('expected string RPC request body');
	}
	return JSON.parse(body);
}

function rpcRequestId(command: unknown): string | number | null {
	if (typeof command === 'object' && command !== null && 'id' in command) {
		const id = command.id;
		if (typeof id === 'string' || typeof id === 'number') {
			return id;
		}
	}
	return null;
}

function rpcMethod(command: unknown): string | null {
	if (typeof command === 'object' && command !== null && 'method' in command) {
		const method = command.method;
		if (typeof method === 'string') {
			return method;
		}
	}
	return null;
}

export function requireMessagePort(port: MessagePort | null): MessagePort {
	if (port === null) {
		throw new Error('expected host intake message port');
	}
	return port;
}

export function makeFileDescriptorFrame(): Extract<
	WorktreeFileProtocolFrame,
	{ readonly frameKind: 'worktree.fileDescriptor' }
> {
	return {
		kind: 'delta',
		frameKind: 'worktree.fileDescriptor',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 1,
		descriptor: {
			path: 'Sources/App.swift',
			fileId: 'file-1',
			contentHandle: 'content-1',
			contentDescriptor: makeAttachedDescriptor('content-1'),
			sourceIdentity: makeSourceIdentity(),
			sizeBytes: 42,
			virtualizedExtentKind: 'exactLineCount',
			lineCount: 2,
			isBinary: false,
			language: 'swift',
			fileExtension: 'swift',
		},
	};
}

export function makeResetFrame(props: {
	readonly generation: number;
	readonly sequence: number;
}): Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.reset' }> {
	return {
		kind: 'reset',
		frameKind: 'worktree.reset',
		streamId: 'worktree-file:pane-1',
		generation: props.generation,
		sequence: props.sequence,
		reason: 'sourceChanged',
		source: makeSourceIdentity({
			subscriptionGeneration: props.generation,
			sourceCursor: `cursor-${props.generation}`,
		}),
	};
}

export function makeTreeWindowFrame(
	props: {
		readonly generation?: number;
		readonly sequence?: number;
		readonly startIndex?: number;
	} = {},
): Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.treeWindow' }> {
	const generation = props.generation ?? 1;
	const sequence = props.sequence ?? 1;
	const startIndex = props.startIndex ?? 1;
	return {
		kind: 'delta',
		frameKind: 'worktree.treeWindow',
		streamId: 'worktree-file:pane-1',
		generation,
		sequence,
		projectionIdentity: {
			source: makeSourceIdentity({
				subscriptionGeneration: generation,
				sourceCursor: `cursor-${generation}`,
			}),
			pathScope: [],
			sortKey: 'path',
			groupKey: 'none',
			filterKey: 'all',
			treeWindowKey: `tree-window-${startIndex}`,
		},
		metadataLineage: {
			loadedBy: 'idle',
			lane: 'idle',
		},
		rows: [
			{
				rowId: 'row:Sources/App.swift',
				path: 'Sources/App.swift',
				name: 'App.swift',
				parentPath: 'Sources',
				depth: 1,
				isDirectory: false,
				fileId: 'file-1',
				sizeBytes: 42,
				lineCount: 2,
			},
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: startIndex + 1,
			rowHeightPixels: 24,
			windowStartIndex: startIndex,
			windowRowCount: 1,
		},
	};
}

export function makeIntakeEnvelope(frame: WorktreeFileProtocolFrame): {
	readonly kind: WorktreeFileProtocolFrame['kind'];
	readonly streamId: string;
	readonly generation: number;
	readonly sequence: number;
	readonly payload: WorktreeFileProtocolFrame;
} {
	return {
		kind: frame.kind,
		streamId: frame.streamId,
		generation: frame.generation,
		sequence: frame.sequence,
		payload: frame,
	};
}

export function makeAttachedDescriptor(
	descriptorId: string,
	props: {
		readonly integrity?: BridgeAttachedResourceDescriptor['descriptor']['content']['integrity'];
		readonly maxBytes?: number;
	} = {},
): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		revision: 1,
	};
	return {
		ref: {
			descriptorId,
			expectedProtocol: 'worktree-file',
			expectedResourceKind: 'worktree.fileContent',
			expectedIdentity: identity,
		},
		descriptor: {
			descriptorId,
			protocol: 'worktree-file',
			resourceKind: 'worktree.fileContent',
			resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/${descriptorId}?generation=1&revision=1`,
			identity,
			content: {
				mediaType: 'text/plain',
				encoding: 'utf-8',
				expectedBytes: 42,
				maxBytes: props.maxBytes ?? 1024,
				...(props.integrity === undefined ? {} : { integrity: props.integrity }),
			},
		},
	};
}

export function chunkedTextResponse(chunks: readonly string[]): Response {
	const encoder = new TextEncoder();
	const body = new ReadableStream<Uint8Array>({
		start(controller): void {
			for (const chunk of chunks) {
				controller.enqueue(encoder.encode(chunk));
			}
			controller.close();
		},
	});
	return Object.assign(new Response(body), {
		text: async (): Promise<string> => {
			throw new Error('whole body text() should not be used for Worktree/File resources');
		},
	});
}
