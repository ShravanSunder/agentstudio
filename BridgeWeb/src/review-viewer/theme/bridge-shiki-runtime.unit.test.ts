import { describe, expect, test } from 'vitest';

import {
	bundledLanguages,
	bundledLanguagesInfo,
	bundledThemes,
	bundledThemesInfo,
	createHighlighter,
	createJavaScriptRegexEngine,
} from './bridge-shiki-runtime.js';

describe('bridgeShikiRuntime', () => {
	test('does not expose bundled Shiki themes', () => {
		expect(bundledThemes).toEqual({});
		expect(bundledThemesInfo).toEqual([]);
	});

	test('exposes only the curated language registry needed by Bridge review', () => {
		expect(bundledLanguages['typescript']).toBeTypeOf('function');
		expect(bundledLanguages['ts']).toBe(bundledLanguages['typescript']);
		expect(bundledLanguages['swift']).toBeTypeOf('function');
		expect(bundledLanguages['markdown']).toBeTypeOf('function');
		expect(bundledLanguages['md']).toBe(bundledLanguages['markdown']);
		expect(bundledLanguages['cpp']).toBeTypeOf('function');
		expect(bundledLanguages['wat']).toBe(bundledLanguages['wasm']);
		expect(bundledLanguagesInfo.length).toBeGreaterThan(20);
	});

	test('creates a Shiki highlighter without requiring a bundled theme', async () => {
		const highlighter = await createHighlighter({
			langs: ['text'],
			themes: [],
			engine: createJavaScriptRegexEngine(),
		});

		highlighter.dispose();
	});
});
