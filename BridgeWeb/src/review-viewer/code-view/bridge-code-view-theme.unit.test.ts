import { readFile } from 'node:fs/promises';

import { describe, expect, test, vi } from 'vitest';

import {
	bridgePierreDarkThemeName,
	ensureBridgeCodeViewThemeResolved,
	type BridgeCodeViewThemeResolver,
} from './bridge-code-view-theme.js';

describe('Bridge CodeView theme', () => {
	test('resolves the bundled Pierre/Shiki Catppuccin Mocha theme', async () => {
		const calls = createThemeResolverCalls();
		const resolver = createThemeResolver({
			calls,
			hasResolvedThemes: (): boolean => false,
		});

		await ensureBridgeCodeViewThemeResolved({ resolver });

		expect(bridgePierreDarkThemeName).toBe('catppuccin-mocha');
		expect(calls.resolveThemes).toEqual([[bridgePierreDarkThemeName]]);
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

	test('uses Catppuccin Mocha tokens in app chrome and CodeView defaults', async () => {
		const css = await readFile(new URL('../../app/bridge-app.css', import.meta.url), 'utf8');
		const lowerCaseCss = css.toLowerCase();

		for (const expectedHexValue of expectedCatppuccinMochaChromeHexValues) {
			expect(lowerCaseCss).toContain(expectedHexValue);
		}
		for (const expectedHexValue of expectedCatppuccinMochaCodeViewHexValues) {
			expect(lowerCaseCss).toContain(expectedHexValue);
		}
	});
});

const expectedCatppuccinMochaChromeHexValues = [
	'#11111b',
	'#1e1e2e',
	'#313244',
	'#6c7086',
	'#bac2de',
	'#cdd6f4',
] as const;

const expectedCatppuccinMochaCodeViewHexValues = [
	'#11111b',
	'#6c7086',
	'#bac2de',
	'#cdd6f4',
	'#89b4fa',
	'#a6e3a1',
	'#f38ba8',
	'#f9e2af',
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
