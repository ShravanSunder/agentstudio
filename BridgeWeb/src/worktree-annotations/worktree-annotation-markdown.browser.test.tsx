import { describe, expect, test } from 'vitest';

import { sanitizeWorktreeAnnotationMarkdownHtml } from './worktree-annotation-markdown.js';

describe('worktree annotation Markdown sanitizer', () => {
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
	});
});
