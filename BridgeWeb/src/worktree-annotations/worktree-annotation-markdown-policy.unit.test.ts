import { describe, expect, test } from 'vitest';

import { validateWorktreeAnnotationMarkdown } from './worktree-annotation-markdown-policy.js';

describe('worktree annotation Markdown policy', () => {
	test('admits H2-H6, tables, lists, fenced code, and absolute web links', () => {
		const markdown = [
			'## Review note',
			'',
			'- Keep the list',
			'- Keep [the source](https://example.com/review?q=1)',
			'',
			'| input | result |',
			'| --- | --- |',
			'| `value` | accepted |',
			'',
			'```html',
			'<h1>Code, not raw HTML</h1>',
			'```',
			'',
			'###### Detail',
		].join('\n');

		expect(validateWorktreeAnnotationMarkdown(markdown)).toEqual({ ok: true });
	});

	test.each([
		['# Level one', 'levelOneHeading'],
		['Level one\n=========', 'levelOneHeading'],
		["<script>alert('no')</script>", 'rawHtml'],
		['[unsafe](javascript:alert(1))', 'unsafeLinkDestination'],
		['[relative](../other.md)', 'unsafeLinkDestination'],
	] as const)('rejects %s as %s', (markdown, code) => {
		expect(validateWorktreeAnnotationMarkdown(markdown)).toEqual({ code, ok: false });
	});

	test('treats H1 and HTML-looking text inside inline code as ordinary code', () => {
		expect(
			validateWorktreeAnnotationMarkdown('Use `# title` and `<section>` as literal values.'),
		).toEqual({ ok: true });
	});

	test('measures the body limit in UTF-8 bytes', () => {
		expect(validateWorktreeAnnotationMarkdown('é'.repeat(8_192))).toEqual({ ok: true });
		expect(validateWorktreeAnnotationMarkdown('é'.repeat(8_193))).toEqual({
			code: 'bodyTooLarge',
			ok: false,
		});
	});
});
