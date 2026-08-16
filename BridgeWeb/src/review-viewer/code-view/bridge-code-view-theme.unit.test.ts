import { readFile } from 'node:fs/promises';

import { resolveThemes } from '@pierre/diffs';
import { describe, expect, test, vi } from 'vitest';

import {
	bridgeGhosttyCatppuccinTreeTheme,
	bridgeViewerTreeStyle,
} from '../../app/bridge-viewer-tree-theme.js';
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

		expect(lowerCaseCss).toContain('--palette-neutral-n1: #282c34;');
		expect(lowerCaseCss).toContain('--palette-text-primary: #ffffff;');
		expect(lowerCaseCss).toContain('--palette-neutral-n0: #1d2026;');
		expect(lowerCaseCss).toContain('--palette-neutral-n3: #323641;');
		expect(lowerCaseCss).toContain('--palette-stroke-subtle: rgb(255 255 255 / 0.1);');
		expect(lowerCaseCss).toContain('--palette-stroke-hover: rgb(255 255 255 / 0.2);');
		expect(lowerCaseCss).toContain('--palette-lavender: #b4befe;');
		expect(lowerCaseCss).toContain('--background: var(--palette-neutral-n1);');
		expect(lowerCaseCss).toContain('--input: var(--palette-stroke-hover);');
		expect(lowerCaseCss).toContain('--diffs-ansi-red: var(--palette-ansi-red);');
		expect(lowerCaseCss).toContain('--diffs-ansi-green: var(--palette-ansi-green);');
		expect(lowerCaseCss).toContain('--diffs-ansi-blue: var(--palette-ansi-blue);');
		expect(lowerCaseCss).toContain('--diffs-focus-border: var(--ring);');

		for (const expectedHexValue of expectedGhosttyAdaptedChromeHexValues) {
			expect(lowerCaseCss).toContain(expectedHexValue);
		}
		for (const expectedHexValue of expectedCatppuccinMochaCodeViewHexValues) {
			expect(lowerCaseCss).toContain(expectedHexValue);
		}
	});

	test('recedes the shared file-tree surface by approximately 1.16 contrast', async () => {
		const css = await readFile(new URL('../../app/bridge-app.css', import.meta.url), 'utf8');
		const canvasColor = readHexCustomProperty(css, '--palette-neutral-n1');
		const fileTreeColor = readHexCustomProperty(css, '--palette-neutral-n0');

		expect(calculateContrastRatio(canvasColor, fileTreeColor)).toBeGreaterThanOrEqual(1.155);
		expect(calculateContrastRatio(canvasColor, fileTreeColor)).toBeLessThanOrEqual(1.17);
	});

	test('raises shared cards and popovers by approximately 1.16 contrast', async () => {
		const css = await readFile(new URL('../../app/bridge-app.css', import.meta.url), 'utf8');
		const canvasColor = readHexCustomProperty(css, '--palette-neutral-n1');
		const raisedSurfaceColor = readHexCustomProperty(css, '--palette-neutral-n3');

		expect(calculateContrastRatio(canvasColor, raisedSurfaceColor)).toBeGreaterThanOrEqual(1.155);
		expect(calculateContrastRatio(canvasColor, raisedSurfaceColor)).toBeLessThanOrEqual(1.17);
	});

	test('anchors the Pierre tree theme to the Ghostty canvas and foreground', () => {
		expect(bridgeGhosttyCatppuccinTreeTheme.bg.toLowerCase()).toBe('#282c34');
		expect(bridgeGhosttyCatppuccinTreeTheme.fg.toLowerCase()).toBe('#ffffff');
		expect(bridgeGhosttyCatppuccinTreeTheme.colors['editor.background'].toLowerCase()).toBe(
			'#282c34',
		);
		expect(bridgeViewerTreeStyle.backgroundColor).toBe('var(--bridge-surface-bg)');
		expect(bridgeViewerTreeStyle.color).toBe('var(--bridge-text-primary)');
	});
});

const expectedGhosttyAdaptedChromeHexValues = [
	'#1d1f21',
	'#1d2026',
	'#282c34',
	'#30343d',
	'#323641',
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

function readHexCustomProperty(css: string, propertyName: string): string {
	const propertyMatch = css.match(new RegExp(`${propertyName}:\\s*(#[0-9a-f]{6});`, 'i'));
	const hexColor = propertyMatch?.[1];
	if (hexColor === undefined) {
		throw new Error(`Missing hexadecimal custom property ${propertyName}`);
	}
	return hexColor;
}

function calculateContrastRatio(firstHexColor: string, secondHexColor: string): number {
	const firstLuminance = calculateRelativeLuminance(firstHexColor);
	const secondLuminance = calculateRelativeLuminance(secondHexColor);
	const lighterLuminance = Math.max(firstLuminance, secondLuminance);
	const darkerLuminance = Math.min(firstLuminance, secondLuminance);
	return (lighterLuminance + 0.05) / (darkerLuminance + 0.05);
}

function calculateRelativeLuminance(hexColor: string): number {
	const redChannel = calculateLinearColorChannel(hexColor, 1);
	const greenChannel = calculateLinearColorChannel(hexColor, 3);
	const blueChannel = calculateLinearColorChannel(hexColor, 5);
	return 0.2126 * redChannel + 0.7152 * greenChannel + 0.0722 * blueChannel;
}

function calculateLinearColorChannel(hexColor: string, startIndex: number): number {
	const channel = Number.parseInt(hexColor.slice(startIndex, startIndex + 2), 16) / 255;
	return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
}
