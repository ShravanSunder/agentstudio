import { describe, expect, test } from 'vitest';

import { buildBridgeMarkdownRenderWorkerSuccessResponse } from './bridge-markdown-render-worker-renderer.js';
import { bridgeMarkdownRenderWorkerRequestSchema } from './bridge-markdown-render-worker-rpc.js';

describe('Bridge markdown render worker RPC', () => {
	test('builds a typed render response with content identity and byte metrics', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-1',
			packageId: 'package-1',
			reviewGeneration: 1,
			revision: 2,
			itemId: 'docs-plan',
			itemVersion: 3,
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			abortKey: 'markdown-preview',
			markdownText: '# Bridge plan',
			sourcePath: 'docs/plans/bridge.md',
		});

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({
			request,
			renderMarkdown: async (markdownText: string): Promise<string> =>
				`<h1>${markdownText.slice(2)}</h1>`,
			now: (() => {
				const samples = [10, 14];
				return (): number => samples.shift() ?? 14;
			})(),
		});

		expect(response).toMatchObject({
			schemaVersion: 1,
			method: 'markdown.render',
			ok: true,
			requestId: 'markdown-request-1',
			packageId: 'package-1',
			reviewGeneration: 1,
			revision: 2,
			itemId: 'docs-plan',
			itemVersion: 3,
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			html: '<h1>Bridge plan</h1>',
			metrics: {
				durationMilliseconds: 4,
				inputBytes: 13,
				outputBytes: 20,
			},
		});
	});

	test('measures awaited markdown render time', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-1',
			packageId: 'package-1',
			reviewGeneration: 1,
			revision: 2,
			itemId: 'docs-plan',
			itemVersion: 3,
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			markdownText: '# Bridge plan',
			sourcePath: 'docs/plans/bridge.md',
		});
		let currentTime = 100;

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({
			request,
			renderMarkdown: async (): Promise<string> => {
				currentTime += 55;
				return '<h1>Bridge plan</h1>';
			},
			now: (): number => currentTime,
		});

		expect(response.metrics.durationMilliseconds).toBe(55);
	});

	test('default renderer keeps raw HTML and bare URLs inert', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-unsafe',
			packageId: 'package-1',
			reviewGeneration: 1,
			revision: 2,
			itemId: 'docs-plan',
			itemVersion: 3,
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			markdownText: [
				'# Bridge plan',
				'',
				'<script>alert(1)</script>',
				'',
				'https://example.com/not-a-link',
				'',
				'```ts',
				'const value = 1;',
				'```',
			].join('\n'),
			sourcePath: 'docs/plans/bridge.md',
		});

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({ request });

		expect(response.html).toContain('<h1>Bridge plan</h1>');
		expect(response.html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
		expect(response.html).not.toContain('<script>');
		expect(response.html).not.toContain('<a href=');
		expect(response.html).toContain('https://example.com/not-a-link');
		expect(response.html).toContain('const');
		expect(response.metrics.inputBytes).toBeGreaterThan(0);
		expect(response.metrics.outputBytes).toBeGreaterThan(0);
	});
});
