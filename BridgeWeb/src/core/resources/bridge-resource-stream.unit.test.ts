import { describe, expect, test } from 'vitest';

import { readBridgeTextResourceStream } from './bridge-resource-stream.js';

describe('bridge resource stream reader', () => {
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
			readText: expect.any(Function),
		});
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
