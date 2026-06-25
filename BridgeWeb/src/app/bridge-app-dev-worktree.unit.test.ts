// @vitest-environment jsdom

import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	installBridgeAppDevWorktreeBackend,
	worktreeFileIncrementalFramesFromSurfaces,
	worktreeFileSourceLessResetFramesFromSurface,
} from './bridge-app-dev-worktree.js';

describe('bridge app dev worktree frame subscription', () => {
	afterEach(() => {
		vi.restoreAllMocks();
		vi.useRealTimers();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		document.documentElement.removeAttribute('data-bridge-worktree-dev-last-reload-status');
	});

	test('derives file invalidation frames when a descriptor content hash changes', () => {
		const previousDescriptor = makeFileDescriptor({
			contentHash: 'sha256:old',
			contentHandle: 'file-content-old',
			cursor: 'cursor-old',
		});
		const nextDescriptor = makeFileDescriptor({
			contentHash: 'sha256:new',
			contentHandle: 'file-content-new',
			cursor: 'cursor-new',
			lineCount: 2,
		});

		const frames = worktreeFileIncrementalFramesFromSurfaces({
			previousFrames: makeFrames(previousDescriptor),
			nextFrames: makeFrames(nextDescriptor),
		});

		expect(frames).toHaveLength(1);
		expect(frames[0]).toMatchObject({
			kind: 'delta',
			frameKind: 'worktree.fileInvalidated',
			invalidation: {
				path: 'src/app.ts',
				fileId: 'file-1',
				reason: 'contentChanged',
				contentHandleIds: ['file-content-old'],
				latestDescriptor: {
					contentHandle: 'file-content-new',
					contentHash: 'sha256:new',
					lineCount: 2,
				},
			},
		});
	});

	test('emits descriptor frames for files added after the initial surface', () => {
		const previousDescriptor = makeFileDescriptor();
		const addedDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-added',
			fileId: 'file-added',
			path: 'src/added.ts',
		});

		const frames = worktreeFileIncrementalFramesFromSurfaces({
			previousFrames: makeFrames(previousDescriptor),
			nextFrames: makeFrames(previousDescriptor, addedDescriptor),
		});

		expect(frames).toHaveLength(1);
		expect(frames[0]).toMatchObject({
			kind: 'delta',
			frameKind: 'worktree.fileDescriptor',
			descriptor: {
				fileId: 'file-added',
				path: 'src/added.ts',
			},
		});
	});

	test('emits a reset and replacement surface when a previous descriptor disappears', () => {
		const previousDescriptor = makeFileDescriptor();
		const survivingDescriptor = makeFileDescriptor({
			contentHandle: 'file-content-surviving',
			fileId: 'file-surviving',
			path: 'src/surviving.ts',
		});

		const frames = worktreeFileIncrementalFramesFromSurfaces({
			previousFrames: makeFrames(previousDescriptor, survivingDescriptor),
			nextFrames: makeFrames(survivingDescriptor),
		});

		expect(frames[0]).toMatchObject({
			kind: 'reset',
			frameKind: 'worktree.reset',
			reason: 'sourceChanged',
		});
		expect(frames.some((frame) => frame.frameKind === 'worktree.snapshot')).toBe(true);
		expect(
			frames
				.filter((frame) => frame.frameKind === 'worktree.fileDescriptor')
				.map((frame) => frame.descriptor.path),
		).toEqual(['src/surviving.ts']);
		expect(frames.map((frame) => frame.sequence)).toEqual([2, 3, 4]);
	});

	test('builds a source-less reset followed by the replacement surface for forced split proof', () => {
		const descriptor = makeFileDescriptor({
			contentHash: 'sha256:replacement',
			contentHandle: 'file-content-replacement',
			cursor: 'cursor-replacement',
		});

		const frames = worktreeFileSourceLessResetFramesFromSurface(makeFrames(descriptor));

		expect(frames[0]).toMatchObject({
			kind: 'reset',
			frameKind: 'worktree.reset',
			reason: 'sourceChanged',
		});
		expect(frames[0]).not.toHaveProperty('source');
		expect(frames[1]).toMatchObject({
			kind: 'snapshot',
			frameKind: 'worktree.snapshot',
			source: { sourceCursor: 'cursor-1' },
		});
		expect(frames.at(-1)).toMatchObject({
			frameKind: 'worktree.fileDescriptor',
			descriptor: {
				contentHandle: 'file-content-replacement',
				contentHash: 'sha256:replacement',
			},
		});
		expect(frames.map((frame) => frame.sequence)).toEqual([2, 3, 4]);
	});

	test('pauses polling reloads while forced split reset proof owns the surface', async () => {
		vi.useFakeTimers();
		const descriptor = makeFileDescriptor();
		let fetchCount = 0;
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (): Promise<Response> => {
			fetchCount += 1;
			return makeSurfaceResponse(makeFrames(descriptor), 'cursor-1');
		});
		const backend = installBridgeAppDevWorktreeBackend();
		await backend.loadWorktreeFileSurface();
		const dispose = backend.subscribeWorktreeFileFrames(() => {});

		window.dispatchEvent(new Event('bridge-worktree-dev-pause-polling'));
		await vi.advanceTimersByTimeAsync(1_000);
		await nextMicrotask();

		expect(fetchCount).toBe(1);
		expect(document.documentElement.dataset['bridgeWorktreeDevPollingState']).toBe('paused');

		window.dispatchEvent(new Event('bridge-worktree-dev-resume-polling'));
		await vi.advanceTimersByTimeAsync(1_000);
		await nextMicrotask();

		expect(fetchCount).toBe(2);
		expect(document.documentElement.dataset['bridgeWorktreeDevPollingState']).toBe('running');
		dispose();
	});

	test('suppresses ordinary poll frames when a forced split reset is queued during reload', async () => {
		vi.useFakeTimers();
		const previousDescriptor = makeFileDescriptor({
			contentHash: 'sha256:old',
			contentHandle: 'file-content-old',
			cursor: 'cursor-old',
		});
		const nextDescriptor = makeFileDescriptor({
			contentHash: 'sha256:new',
			contentHandle: 'file-content-new',
			cursor: 'cursor-new',
		});
		const normalReload = makeDeferred<Response>();
		const forceReload = makeDeferred<Response>();
		const surfaceResponses: Promise<Response>[] = [
			Promise.resolve(makeSurfaceResponse(makeFrames(previousDescriptor), 'cursor-old')),
			normalReload.promise,
			forceReload.promise,
		];
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (): Promise<Response> => {
			const nextResponse = surfaceResponses.shift();
			if (nextResponse === undefined) {
				throw new Error('Unexpected worktree surface fetch');
			}
			return await nextResponse;
		});
		const backend = installBridgeAppDevWorktreeBackend();
		await backend.loadWorktreeFileSurface();
		const deliveredFrameBatches: Array<readonly WorktreeFileProtocolFrame[]> = [];
		const dispose = backend.subscribeWorktreeFileFrames((frames) => {
			deliveredFrameBatches.push(frames);
		});

		window.dispatchEvent(new Event('bridge-worktree-dev-reload'));
		window.dispatchEvent(new Event('bridge-worktree-dev-force-split-reset-reload'));
		normalReload.resolve(makeSurfaceResponse(makeFrames(nextDescriptor), 'cursor-new'));
		await nextMicrotask();

		expect(deliveredFrameBatches).toEqual([]);

		forceReload.resolve(makeSurfaceResponse(makeFrames(nextDescriptor), 'cursor-new'));
		await nextMicrotask();
		await vi.advanceTimersByTimeAsync(0);
		await nextMicrotask();

		expect(deliveredFrameBatches.map((batch) => batch.map((frame) => frame.frameKind))).toEqual([
			['worktree.reset'],
			['worktree.snapshot', 'worktree.fileDescriptor'],
		]);
		expect(
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameKinds'],
		).toBe('worktree.reset,worktree.snapshot,worktree.fileDescriptor');
		expect(
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameSequences'],
		).toBe('2,3,4');
		expect(
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'],
		).toBe('cursor-new');
		dispose();
	});
});

function makeFrames(
	...descriptors: readonly WorktreeFileDescriptor[]
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'snapshot',
			streamId: 'worktree-file:pane-1',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.snapshot',
			source: makeSourceIdentity('cursor-1'),
			treeDescriptor: makeAttachedDescriptor({
				cursor: 'cursor-1',
				descriptorId: 'tree-window-1',
				resourceKind: 'worktree.treeWindow',
			}),
			treeSizeFacts: {
				pathCount: descriptors.length,
				windowStartIndex: 0,
				windowRowCount: descriptors.length,
				rowHeightPixels: 24,
			},
		},
		...descriptors.map(
			(descriptor, index): WorktreeFileProtocolFrame => ({
				kind: 'delta',
				streamId: 'worktree-file:pane-1',
				generation: 1,
				sequence: index + 1,
				frameKind: 'worktree.fileDescriptor',
				descriptor,
			}),
		),
	];
}

interface MakeFileDescriptorProps {
	readonly contentHandle?: string;
	readonly contentHash?: string;
	readonly cursor?: string;
	readonly fileId?: string;
	readonly lineCount?: number;
	readonly path?: string;
}

function makeFileDescriptor(props: MakeFileDescriptorProps = {}): WorktreeFileDescriptor {
	const contentHandle = props.contentHandle ?? 'file-content-1';
	const cursor = props.cursor ?? 'cursor-1';
	return {
		path: props.path ?? 'src/app.ts',
		fileId: props.fileId ?? 'file-1',
		contentHandle,
		contentDescriptor: makeAttachedDescriptor({
			cursor,
			descriptorId: contentHandle,
			resourceKind: 'worktree.fileContent',
		}),
		contentHash: props.contentHash ?? 'sha256:default',
		sourceIdentity: makeSourceIdentity(cursor),
		sizeBytes: 24,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: props.lineCount ?? 1,
		isBinary: false,
		language: 'typescript',
		fileExtension: 'ts',
	};
}

function makeSourceIdentity(cursor: string): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: cursor,
	};
}

function makeAttachedDescriptor(props: {
	readonly cursor: string;
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent' | 'worktree.treeWindow';
}): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
		cursor: props.cursor,
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'worktree-file',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/worktree-file/${props.resourceKind}/${props.descriptorId}?generation=1&cursor=${props.cursor}`,
		identity,
		content: {
			mediaType: 'text/plain',
			encoding: 'utf-8',
			expectedBytes: 64,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		},
		descriptor,
	});
}

function makeSurfaceResponse(
	frames: readonly WorktreeFileProtocolFrame[],
	sourceCursor: string,
): Response {
	return new Response(
		JSON.stringify({
			frames,
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'worktree-root-token',
			},
			source: makeSourceIdentity(sourceCursor),
			treeSizeFacts: {
				pathCount: worktreeFileDescriptorCount(frames),
				rowHeightPixels: 24,
			},
		}),
		{
			headers: { 'content-type': 'application/json' },
			status: 200,
		},
	);
}

function worktreeFileDescriptorCount(frames: readonly WorktreeFileProtocolFrame[]): number {
	return frames.filter((frame) => frame.frameKind === 'worktree.fileDescriptor').length;
}

function makeDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
} {
	let resolveValue: ((value: TValue) => void) | undefined;
	const promise = new Promise<TValue>((resolve) => {
		resolveValue = resolve;
	});
	if (resolveValue === undefined) {
		throw new Error('Expected deferred resolver to be initialized');
	}
	return {
		promise,
		resolve: resolveValue,
	};
}

async function nextMicrotask(): Promise<void> {
	await Promise.resolve();
}
