import { readFile } from 'node:fs/promises';

import { resolveThemes } from '@pierre/diffs';
import { describe, expect, test, vi } from 'vitest';

import { bridgeGhosttyCatppuccinTreeTheme } from '../../app/bridge-viewer-tree-theme.js';
import {
	bridgePierreDarkThemeName,
	ensureBridgeCodeViewThemeResolved,
	type BridgeCodeViewThemeResolver,
} from './bridge-code-view-theme.js';

describe('Bridge CodeView theme', () => {
	test('registers Catppuccin Mocha with the default Pierre theme resolver', async () => {
		await expect(ensureBridgeCodeViewThemeResolved()).resolves.toBeUndefined();
		await expect(ensureBridgeCodeViewThemeResolved()).resolves.toBeUndefined();
	});

	test('resolves the Agent Studio Ghostty-anchored Catppuccin theme', async () => {
		const calls = createThemeResolverCalls();
		const resolver = createThemeResolver({
			calls,
			hasResolvedThemes: (): boolean => false,
		});

		await ensureBridgeCodeViewThemeResolved({ resolver });

		expect(bridgePierreDarkThemeName).toBe('agentstudio-ghostty-dark');
		expect(calls.resolveThemes).toEqual([[bridgePierreDarkThemeName]]);
	});

	test('uses Ghostty defaults for the resolved Pierre canvas and foreground', async () => {
		await ensureBridgeCodeViewThemeResolved();

		const [resolvedTheme] = await resolveThemes([bridgePierreDarkThemeName]);

		expect(resolvedTheme?.bg.toLowerCase()).toBe('#282c34');
		expect(resolvedTheme?.fg.toLowerCase()).toBe('#ffffff');
	});

	test('skips resolution when the theme is already resolved', async () => {
		const calls = createThemeResolverCalls();
		const resolver = createThemeResolver({
			calls,
			hasResolvedThemes: (): boolean => true,
		});

		await ensureBridgeCodeViewThemeResolved({ resolver });

		expect(calls.resolveThemes).toEqual([]);
	});

	test('uses Ghostty-anchored neutrals with Catppuccin accents in app chrome', async () => {
		const css = await readFile(new URL('../../app/bridge-app.css', import.meta.url), 'utf8');
		const lowerCaseCss = css.toLowerCase();

		expect(lowerCaseCss).toContain('--background: #282c34;');
		expect(lowerCaseCss).toContain('--foreground: #ffffff;');
		expect(lowerCaseCss).toContain('--bridge-app-bg: #282c34;');
		expect(lowerCaseCss).toContain('--bridge-canvas-bg: #282c34;');
		expect(lowerCaseCss).toContain('--bridge-header-bg: #23262d;');
		expect(lowerCaseCss).toContain('--bridge-surface-bg: #23262d;');
		expect(lowerCaseCss).toContain('--border: rgb(255 255 255 / 0.1);');
		expect(lowerCaseCss).toContain('--input: rgb(255 255 255 / 0.18);');
		expect(lowerCaseCss).toContain('--ring: #b4befe;');
		expect(lowerCaseCss).toContain('--bridge-border-subtle: var(--border);');
		expect(lowerCaseCss).toContain('--bridge-border-opaque: var(--input);');
		expect(lowerCaseCss).toContain('--bridge-focus-border: var(--ring);');
		expect(lowerCaseCss).toContain('--diffs-ansi-red: #cc6666;');
		expect(lowerCaseCss).toContain('--diffs-ansi-green: #b5bd68;');
		expect(lowerCaseCss).toContain('--diffs-ansi-blue: #81a2be;');
		expect(lowerCaseCss).toContain(
			'--bridge-code-view-file-separator: var(--bridge-border-opaque);',
		);
		expect(lowerCaseCss).toContain('--diffs-focus-border: var(--bridge-focus-border);');

		for (const expectedHexValue of expectedGhosttyAdaptedChromeHexValues) {
			expect(lowerCaseCss).toContain(expectedHexValue);
		}
		for (const expectedHexValue of expectedCatppuccinMochaCodeViewHexValues) {
			expect(lowerCaseCss).toContain(expectedHexValue);
		}
	});

	test('anchors the Pierre tree theme to the Ghostty canvas and foreground', () => {
		expect(bridgeGhosttyCatppuccinTreeTheme.bg.toLowerCase()).toBe('#282c34');
		expect(bridgeGhosttyCatppuccinTreeTheme.fg.toLowerCase()).toBe('#ffffff');
		expect(bridgeGhosttyCatppuccinTreeTheme.colors['editor.background'].toLowerCase()).toBe(
			'#282c34',
		);
	});
});

const expectedGhosttyAdaptedChromeHexValues = [
	'#1d1f21',
	'#23262d',
	'#282c34',
	'#30343d',
	'#343842',
	'#9ba1ad',
	'#c5c8c6',
	'#ffffff',
] as const;

const expectedCatppuccinMochaCodeViewHexValues = [
	'#89b4fa',
	'#a6e3a1',
	'#b4befe',
	'#cba6f7',
	'#f38ba8',
	'#f9e2af',
	'#fab387',
] as const;

interface ThemeResolverCallLog {
	readonly resolveThemes: Array<readonly string[]>;
}

function createThemeResolverCalls(): ThemeResolverCallLog {
	return {
		resolveThemes: [],
	};
}

interface CreateThemeResolverProps {
	readonly calls: ThemeResolverCallLog;
	readonly hasResolvedThemes: (themeNames: readonly string[]) => boolean;
}

function createThemeResolver(props: CreateThemeResolverProps): BridgeCodeViewThemeResolver {
	return {
		hasResolvedThemes: vi.fn(props.hasResolvedThemes),
		resolveThemes: vi.fn(async (themeNames: readonly string[]): Promise<readonly unknown[]> => {
			props.calls.resolveThemes.push(themeNames);
			return themeNames.map((themeName: string): { readonly name: string } => ({
				name: themeName,
			}));
		}),
	};
}
