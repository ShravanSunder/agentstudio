import { describe, expect, test } from 'vitest';

import type { BridgeWorkerFileViewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { fetchBridgeWorkerFileViewContentResource } from './bridge-worker-file-view-content-fetch.js';

describe('Bridge worker File View content fetch', () => {
	test('fetches typed File View content descriptors through injected worker fetch', async () => {
		const calls: string[] = [];
		const result = await fetchBridgeWorkerFileViewContentResource({
			descriptor: makeContentRequestDescriptor(),
			fetchContent: async (url: string): Promise<Response> => {
				calls.push(url);
				return new Response('hello file worker');
			},
		});

		expect(calls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&generation=4',
		]);
		expect(result).toMatchObject({
			itemId: 'file-1',
			path: 'Sources/App/FileView.swift',
			descriptorId: 'descriptor-file-1',
			resourceKind: 'worktree.fileContent',
			contentHash: 'sha256:file-1',
			contentHashAlgorithm: 'sha256',
			language: 'swift',
			byteLength: 17,
		});
		expect(result.textBytes.byteLength).toBe(17);
		expect(new TextDecoder().decode(result.textBytes)).toBe('hello file worker');
	});

	test('returns the original fetched bytes without re-encoding decoded text', async () => {
		const originalBytes = new Uint8Array([0xef, 0xbb, 0xbf, 0x61]);

		const result = await fetchBridgeWorkerFileViewContentResource({
			descriptor: makeContentRequestDescriptor(),
			fetchContent: async (): Promise<Response> => new Response(originalBytes),
		});

		expect(result.byteLength).toBe(4);
		expect([...new Uint8Array(result.textBytes)]).toEqual([...originalBytes]);
		expect(result.text).toBe('a');
	});

	test('rejects File View descriptor resource urls that are missing cursor or mismatch descriptorId before fetch', async () => {
		const fetchCalls: string[] = [];

		await expect(
			fetchBridgeWorkerFileViewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?generation=4',
				},
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return new Response('must not fetch');
				},
			}),
		).rejects.toThrow(/resource url/i);
		await expect(
			fetchBridgeWorkerFileViewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.fileContent/other-descriptor?cursor=cursor-1&generation=4',
				},
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return new Response('must not fetch');
				},
			}),
		).rejects.toThrow(/resource url/i);
		expect(fetchCalls).toEqual([]);
	});

	test('rejects binary File View descriptors before text fetch', async () => {
		const fetchCalls: string[] = [];

		await expect(
			fetchBridgeWorkerFileViewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					isBinary: true,
				},
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return new Response('must not fetch');
				},
			}),
		).rejects.toThrow(/binary/i);
		expect(fetchCalls).toEqual([]);
	});

	test('uses File View descriptor maxBytes as the stream limit', async () => {
		await expect(
			fetchBridgeWorkerFileViewContentResource({
				descriptor: {
					...makeContentRequestDescriptor(),
					maxBytes: 5,
					sizeBytes: 10_000,
				},
				fetchContent: async (): Promise<Response> => new Response('exceeds max bytes'),
			}),
		).rejects.toThrow(/max bytes|byte/i);
	});
});

function makeContentRequestDescriptor(): BridgeWorkerFileViewContentRequestDescriptor {
	return {
		itemId: 'file-1',
		path: 'Sources/App/FileView.swift',
		handleId: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		resourceKind: 'worktree.fileContent',
		resourceUrl:
			'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-1&generation=4',
		contentHash: 'sha256:file-1',
		contentHashAlgorithm: 'sha256',
		language: 'swift',
		sizeBytes: 10_000,
		maxBytes: 1024,
		isBinary: false,
	};
}
