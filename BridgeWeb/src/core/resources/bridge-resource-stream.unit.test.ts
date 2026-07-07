import { describe, expect, test } from 'vitest';

import {
	bridgeTextResourceLoadErrorKind,
	loadBridgeTextResourceWithTiming,
	readBridgeTextResourceStream,
} from './bridge-resource-stream.js';

describe('bridge resource stream reader', () => {
	test('classifies HTTP response failures without exposing raw response bodies', async () => {
		await expect(
			loadBridgeTextResourceWithTiming({
				performFetch: async (): Promise<Response> => new Response('not found', { status: 404 }),
			}),
		).rejects.toMatchObject({
			kind: 'http_error',
		});
	});

	test('classifies final integrity mismatches for diagnostics', async () => {
		try {
			await readBridgeTextResourceStream(chunkedTextResponse(['tampered ', 'bridge']), {
				integrity: {
					kind: 'wholeHash',
					algorithm: 'sha256',
					value: 'sha256:3173778af72bee80065ddb3dc0fa2319fcaca233bdfd4591d1b3a4ca5115d5a9',
				},
			});
		} catch (error: unknown) {
			expect(bridgeTextResourceLoadErrorKind(error)).toBe('integrity_mismatch');
			return;
		}
		throw new Error('expected integrity mismatch');
	});

	test('rejects a stream once it exceeds the issued max byte limit', async () => {
		await expect(
			readBridgeTextResourceStream(chunkedTextResponse(['abcd', 'ef']), {
				maxBytes: 5,
			}),
		).rejects.toThrow('Bridge text resource stream exceeded issued max bytes');
	});

	test('rejects a whole-body resource when final sha256 integrity mismatches', async () => {
		await expect(
			readBridgeTextResourceStream(chunkedTextResponse(['tampered ', 'bridge']), {
				integrity: {
					kind: 'wholeHash',
					algorithm: 'sha256',
					value: 'sha256:3173778af72bee80065ddb3dc0fa2319fcaca233bdfd4591d1b3a4ca5115d5a9',
				},
			}),
		).rejects.toThrow('Bridge text resource stream failed whole-body integrity validation');
	});

	test('accepts streamed text when final sha256 integrity matches', async () => {
		const result = await readBridgeTextResourceStream(chunkedTextResponse(['hello ', 'bridge']), {
			integrity: {
				kind: 'wholeHash',
				algorithm: 'sha256',
				value: 'sha256:af967f619c7e16dae9cce287b0ac3e399b29721ee73c37536df35dfbaf5fd0cd',
			},
			maxBytes: 64,
		});

		expect(result).toEqual({
			authoritative: true,
			byteLength: 12,
			copyBytes: expect.any(Function),
			readText: expect.any(Function),
		});
		expect([...new Uint8Array(result.copyBytes())]).toEqual([
			...new TextEncoder().encode('hello bridge'),
		]);
		expect(result.readText()).toBe('hello bridge');
	});

	test('emits decoded text chunks before the final materialized text resolves', async () => {
		const textChunks: string[] = [];
		let resultSettled = false;

		const result = await readBridgeTextResourceStream(
			chunkedTextResponse(['visible ', 'range ', 'body']),
			{
				maxBytes: 64,
				onTextChunk: (chunk): void => {
					textChunks.push(chunk.text);
					expect(resultSettled).toBe(false);
				},
			},
		);
		resultSettled = true;

		expect(textChunks).toEqual(['visible ', 'range ', 'body']);
		expect(result.readText()).toBe('visible range body');
	});

	test('flushes a final decoded text chunk when utf8 spans stream chunks', async () => {
		const textChunks: string[] = [];
		const encoder = new TextEncoder();
		const euroBytes = encoder.encode('€');

		const result = await readBridgeTextResourceStream(
			chunkedByteResponse([euroBytes.slice(0, 1), euroBytes.slice(1)]),
			{
				maxBytes: 8,
				onTextChunk: (chunk): void => {
					if (chunk.text.length > 0) {
						textChunks.push(chunk.text);
					}
				},
			},
		);

		expect(textChunks).toEqual(['€']);
		expect(result.readText()).toBe('€');
	});

	test('measures fetch response wait, first chunk wait, and stream read duration', async () => {
		const timestamps = [100, 130, 131, 134, 140];
		const textChunks: string[] = [];

		const result = await loadBridgeTextResourceWithTiming({
			maxBytes: 64,
			probe: {
				isEnabled: (): boolean => true,
				now: (): number => {
					const timestamp = timestamps.shift();
					if (timestamp === undefined) {
						throw new Error('unexpected extra timing sample');
					}
					return timestamp;
				},
			},
			onTextChunk: (chunk): void => {
				textChunks.push(chunk.text);
			},
			performFetch: async (): Promise<Response> => chunkedTextResponse(['hello ', 'timing']),
		});

		expect(result.timing).toEqual({
			firstChunkWaitMilliseconds: 3,
			responseWaitMilliseconds: 30,
			streamReadMilliseconds: 9,
		});
		expect(textChunks).toEqual(['hello ', 'timing']);
		expect(result.readText()).toBe('hello timing');
	});

	test('skips timing work when no probe is provided', async () => {
		const result = await loadBridgeTextResourceWithTiming({
			maxBytes: 64,
			onTextChunk: (): void => {},
			performFetch: async (): Promise<Response> => chunkedTextResponse(['cold ', 'path']),
		});

		expect(result.timing).toBeUndefined();
		expect(result.readText()).toBe('cold path');
	});

	test('skips timing work when the probe is disabled', async () => {
		const result = await loadBridgeTextResourceWithTiming({
			maxBytes: 64,
			probe: {
				isEnabled: (): boolean => false,
				now: (): number => {
					throw new Error('disabled probe should not be sampled');
				},
			},
			performFetch: async (): Promise<Response> => chunkedTextResponse(['disabled ', 'probe']),
		});

		expect(result.timing).toBeUndefined();
		expect(result.readText()).toBe('disabled probe');
	});
});

function chunkedTextResponse(chunks: readonly string[]): Response {
	const encoder = new TextEncoder();
	return chunkedByteResponse(chunks.map((chunk) => encoder.encode(chunk)));
}

function chunkedByteResponse(chunks: readonly Uint8Array[]): Response {
	const body = new ReadableStream<Uint8Array>({
		start(controller): void {
			for (const chunk of chunks) {
				controller.enqueue(chunk);
			}
			controller.close();
		},
	});
	return Object.assign(new Response(body), {
		text: async (): Promise<string> => {
			throw new Error('whole body text() should not be used for Bridge content resources');
		},
	});
}
