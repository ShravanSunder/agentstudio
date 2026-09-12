import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import { buildBridgeMarkdownRenderWorkerSuccessResponse } from '../app/markdown/worker/bridge-markdown-render-worker-renderer.js';
import {
	WorktreeAnnotationMarkdown,
	sanitizeWorktreeAnnotationMarkdownHtml,
} from './worktree-annotation-markdown.js';

// oxlint-disable-next-line import/no-unassigned-import -- Verify code presentation after the production sanitizer.
import '../app/bridge-app.css';

describe('worktree annotation Markdown sanitizer', () => {
	test('preserves real worker code indentation, blank lines and monospace presentation', async (): Promise<void> => {
		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({
			request: {
				schemaVersion: 1,
				method: 'markdown.render',
				requestId: 'annotation-code-proof',
				sourceIdentity: {
					surface: 'file',
					sourceId: 'session',
					sourceGeneration: 1,
					fileId: 'message',
					fileVersion: 1,
				},
				contentCacheKey: 'message:1',
				contentHash: 'message:1',
				sourcePath: 'annotation.md',
				markdownText: '```ts\n  const value = 1;\n\n    return value;\n```',
			},
		});
		const screen = await render(<WorktreeAnnotationMarkdown html={response.htmlCandidate} />);
		const body = screen.getByTestId('worktree-annotation-markdown').element();
		const lines = body.querySelectorAll<HTMLElement>('.bridge-markdown-code-lines > .line');
		expect(lines).toHaveLength(3);
		expect(lines[0]?.textContent).toBe('  const value = 1;');
		expect(lines[2]?.textContent).toBe('    return value;');
		for (const line of lines) {
			expect(getComputedStyle(line).whiteSpace).toBe('pre');
			expect(getComputedStyle(line).fontFamily).toContain('monospace');
			expect(line.getBoundingClientRect().height).toBeGreaterThan(0);
		}
		expect(body.querySelector('[data-bridge-markdown-target]')).toBeNull();
	});
	test('keeps only absolute HTTP(S) href values and narrow Shiki presentation attributes', () => {
		const sanitized = sanitizeWorktreeAnnotationMarkdownHtml(
			[
				'<h1>forbidden packet heading</h1>',
				'<h2 data-owner="unsafe">Review note</h2>',
				'<a href="https://example.com/review" target="_blank" rel="opener" onclick="alert(1)">safe</a>',
				'<a href="javascript:alert(1)" data-owner="unsafe">unsafe</a>',
				'<a href="../relative.md">relative</a>',
				'<pre class="shiki github-dark" style="background-color:#0d1117;color:#e6edf3;position:fixed"><code><span class="line" style="color:#ff0000;background-image:url(https://example.com/x)">const value = 1</span></code></pre>',
				'<img src="https://example.com/tracker.png">',
				'<div class="bridge-markdown-code-lines attacker" style="position:fixed" data-bridge-markdown-target="spoof"><div class="line attacker" onclick="alert(1)">safe code</div></div>',
			].join(''),
		);
		const template = document.createElement('template');
		template.innerHTML = sanitized;

		expect(template.content.querySelector('h1')).toBeNull();
		expect(template.content.querySelector('h2')?.attributes).toHaveLength(0);
		const anchors = template.content.querySelectorAll('a');
		expect(anchors[0]?.getAttribute('href')).toBe('https://example.com/review');
		expect(anchors[0]?.attributes).toHaveLength(1);
		expect(anchors[1]?.hasAttribute('href')).toBe(false);
		expect(anchors[1]?.attributes).toHaveLength(0);
		expect(anchors[2]?.hasAttribute('href')).toBe(false);
		expect(template.content.querySelector('img')).toBeNull();
		expect(template.content.querySelector('pre')?.getAttribute('class')).toBe('shiki github-dark');
		expect(template.content.querySelector('pre')?.getAttribute('style')).toBe(
			'background-color: #0d1117; color: #e6edf3',
		);
		expect(template.content.querySelector('span')?.getAttribute('style')).toBe('color: #ff0000');
		const codeContainer = template.content.querySelector('div');
		expect(codeContainer?.getAttribute('class')).toBe('bridge-markdown-code-lines');
		expect(codeContainer?.attributes).toHaveLength(1);
		expect(codeContainer?.firstElementChild?.getAttribute('class')).toBe('line');
		expect(codeContainer?.firstElementChild?.attributes).toHaveLength(1);
	});
});
