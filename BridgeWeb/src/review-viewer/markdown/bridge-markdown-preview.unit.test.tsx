// @vitest-environment jsdom

import { describe, expect, test } from 'vitest';

import { BridgeMarkdownPreview, sanitizeBridgeMarkdownHtml } from './bridge-markdown-preview.js';

describe('Bridge markdown preview', () => {
	test('sanitizes repository markdown HTML before DOM insertion', () => {
		const sanitizedHtml = sanitizeBridgeMarkdownHtml(
			'<h1>Plan</h1><img src=x onerror="alert(1)"><script>alert(1)</script>',
		);

		expect(sanitizedHtml).toContain('<h1>Plan</h1>');
		expect(sanitizedHtml).not.toContain('<img');
		expect(sanitizedHtml).not.toContain('<script>');
		expect(sanitizedHtml).not.toContain('onerror');
	});

	test('keeps repository markdown links and media inert', () => {
		const sanitizedHtml = sanitizeBridgeMarkdownHtml(
			'<p><a href="https://example.com/track">link</a><img src="https://example.com/track.png" alt="tracker"><video src="https://example.com/movie.mp4"></video></p>',
		);

		expect(sanitizedHtml).toContain('<a>link</a>');
		expect(sanitizedHtml).not.toContain('href=');
		expect(sanitizedHtml).not.toContain('src=');
		expect(sanitizedHtml).not.toContain('<img');
		expect(sanitizedHtml).not.toContain('<video');
	});

	test('removes file data javascript and custom-scheme resource attributes', () => {
		const sanitizedHtml = sanitizeBridgeMarkdownHtml(
			[
				'<a href="file:///Users/example/.ssh/id_rsa">file</a>',
				'<a href="data:text/html;base64,PHNjcmlwdD4=">data</a>',
				'<a href="javascript:alert(1)">javascript</a>',
				'<img src="agentstudio://resource/review/content/secret?generation=1">',
				'<source srcset="bridge://private">',
				'<table background="https://example.com/tracker.png"><tr><td>legacy</td></tr></table>',
				'<blockquote cite="https://example.com/quote">quote</blockquote>',
			].join(''),
		);

		expect(sanitizedHtml).toContain('<a>file</a>');
		expect(sanitizedHtml).toContain('<a>data</a>');
		expect(sanitizedHtml).toContain('<a>javascript</a>');
		expect(sanitizedHtml).not.toContain('href=');
		expect(sanitizedHtml).not.toContain('src=');
		expect(sanitizedHtml).not.toContain('srcset=');
		expect(sanitizedHtml).not.toContain('background=');
		expect(sanitizedHtml).not.toContain('cite=');
		expect(sanitizedHtml).not.toContain('file://');
		expect(sanitizedHtml).not.toContain('data:');
		expect(sanitizedHtml).not.toContain('javascript:');
		expect(sanitizedHtml).not.toContain('agentstudio://');
		expect(sanitizedHtml).not.toContain('bridge://');
		expect(sanitizedHtml).not.toContain('https://example.com');
	});

	test('preserves constrained Shiki styles and drops unsafe style properties', () => {
		const sanitizedHtml = sanitizeBridgeMarkdownHtml(
			'<pre style="background-color:#0d1117;background-image:url(https://example.com/x.png)"><code><span style="color:#79c0ff;position:fixed">let</span></code></pre>',
		);

		expect(sanitizedHtml).toContain('style="background-color: #0d1117"');
		expect(sanitizedHtml).toContain('style="color: #79c0ff"');
		expect(sanitizedHtml).not.toContain('background-image');
		expect(sanitizedHtml).not.toContain('position');
		expect(sanitizedHtml).not.toContain('url(');
	});

	test('strips interactive controls from repository markdown HTML', () => {
		const sanitizedHtml = sanitizeBridgeMarkdownHtml(
			[
				'<form action="/submit"><input autofocus value="secret"><button onclick="alert(1)">Run</button></form>',
				'<details open><summary>Reveal</summary><p>Hidden text</p></details>',
				'<dialog open>Modal</dialog>',
				'<p contenteditable="true" tabindex="0" onfocus="alert(1)">editable</p>',
			].join(''),
		);

		expect(sanitizedHtml).not.toContain('<form');
		expect(sanitizedHtml).not.toContain('<input');
		expect(sanitizedHtml).not.toContain('<button');
		expect(sanitizedHtml).not.toContain('<details');
		expect(sanitizedHtml).not.toContain('<summary');
		expect(sanitizedHtml).not.toContain('<dialog');
		expect(sanitizedHtml).not.toContain('autofocus');
		expect(sanitizedHtml).not.toContain('contenteditable');
		expect(sanitizedHtml).not.toContain('tabindex');
		expect(sanitizedHtml).not.toContain('onfocus');
	});

	test('renders sanitized HTML in a bounded preview surface', () => {
		const element = BridgeMarkdownPreview({
			html: '<h1>Bridge plan</h1><script>alert(1)</script>',
			sourcePath: 'docs/plans/bridge.md',
		});

		expect(element.props['data-testid']).toBe('bridge-markdown-preview');
		expect(element.props['data-markdown-preview-source-path']).toBe('docs/plans/bridge.md');
		const renderedHtml = Object.values(element.props.dangerouslySetInnerHTML).join('');
		expect(renderedHtml).toContain('Bridge plan');
		expect(renderedHtml).not.toContain('<script>');
		expect(element.props.className).toContain('max-w-[920px]');
	});
});
