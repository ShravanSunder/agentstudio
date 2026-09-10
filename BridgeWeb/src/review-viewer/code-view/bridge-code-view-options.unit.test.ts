import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import { bridgeFileViewerCodeViewOptions } from '../../file-viewer/bridge-file-viewer-code-view-options.js';
import { bridgeCodeViewOptions } from './bridge-code-view-options.js';

describe('Bridge CodeView options', () => {
	test('uses one quiet file boundary without input-colored container shadows', async () => {
		const frameSource = await readFile(
			new URL('./bridge-code-view-panel-frame.tsx', import.meta.url),
			'utf8',
		);
		expect(bridgeCodeViewOptions.unsafeCSS).toContain(
			'border-block-start: 1px solid var(--separator);',
		);
		expect(frameSource).not.toContain('[&_diffs-container]:shadow-');
	});

	test('binds canonical code and header fonts on the Pierre host boundary', async () => {
		const css = await readFile(new URL('../../app/bridge-app.css', import.meta.url), 'utf8');
		const codeViewHostRule = css.match(/\.bridge-code-view-panel\s*\{(?<declarations>[^}]*)\}/)
			?.groups?.['declarations'];

		expect(css).toContain('--text-sm: 12px;');
		expect(codeViewHostRule).toContain('--diffs-font-size: var(--text-sm);');
		expect(codeViewHostRule).toContain('--diffs-font-family: var(--font-mono);');
		expect(codeViewHostRule).toContain('--diffs-header-font-family: var(--font-sans);');
	});

	test('preserves effective renderer hooks while removing transitional aliases', () => {
		const unsafeCSS = bridgeCodeViewOptions.unsafeCSS ?? '';
		const codeHeaderRule = unsafeCSS.match(/\[data-diffs-header\]\s*\{(?<declarations>[^}]*)\}/)
			?.groups?.['declarations'];

		expect(unsafeCSS).not.toContain('--bridge-');
		expect(codeHeaderRule).toContain('--diffs-addition-base: var(--success);');
		expect(codeHeaderRule).toContain('--diffs-deletion-base: var(--destructive);');
		expect(codeHeaderRule).toContain('--diffs-modified-base: var(--primary);');
		expect(codeHeaderRule).toContain('--diffs-fg: var(--code-foreground);');
		expect(codeHeaderRule).toContain('--diffs-fg-number: var(--faint-foreground);');
		expect(codeHeaderRule).toContain('background-color: var(--file-header);');
		expect(codeHeaderRule).toContain('height: 40px;');
		expect(codeHeaderRule).toContain('min-height: 40px;');
		expect(unsafeCSS).toContain('--diffs-computed-selected-line-bg: var(--diffs-annotation-bg);');
		expect(unsafeCSS).toContain('--diffs-line-bg: var(--diffs-annotation-bg);');
		expect(unsafeCSS).toContain('--diffs-annotation-bg: var(--annotation-lane-background);');
		expect(unsafeCSS).toContain('--diffs-annotation-bg: var(--annotation-lane-active-background);');
		expect(bridgeCodeViewOptions.itemMetrics?.diffHeaderHeight).toBe(40);
	});

	test('carries the common Pierre host contract into the File viewer adapter', () => {
		expect(bridgeFileViewerCodeViewOptions.unsafeCSS).toContain(bridgeCodeViewOptions.unsafeCSS);
		expect(bridgeFileViewerCodeViewOptions.unsafeCSS).not.toContain('--bridge-');
	});
});
