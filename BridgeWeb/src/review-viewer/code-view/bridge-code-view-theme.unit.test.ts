import { readFile } from 'node:fs/promises';

import { resolveThemes } from '@pierre/diffs';
import catppuccinMochaTheme from '@shikijs/themes/catppuccin-mocha';
import { describe, expect, test, vi } from 'vitest';

import {
	bridgeGhosttyCatppuccinTreeTheme,
	bridgeGhosttyCatppuccinTreeStyles,
	bridgeViewerTreeStyle,
	bridgeViewerTreeUnsafeCSS,
} from '../../app/bridge-viewer-tree-theme.js';
import { bridgeDesignPalette } from '../../design-tokens/bridge-design-palette.js';
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

		expect(resolvedTheme?.bg.toLowerCase()).toBe(
			bridgeDesignPalette['--palette-neutral-n1'].toLowerCase(),
		);
		expect(resolvedTheme?.fg.toLowerCase()).toBe(
			bridgeDesignPalette['--palette-text-primary'].toLowerCase(),
		);
		expect(resolvedTheme?.settings).toEqual(catppuccinMochaTheme.tokenColors);
		expect(resolvedTheme?.semanticTokenColors).toEqual(catppuccinMochaTheme.semanticTokenColors);
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

	test('supplies only reachable palette-backed fields to the installed tree theme adapter', () => {
		expect(bridgeGhosttyCatppuccinTreeTheme).toEqual({
			type: 'dark',
			fg: bridgeDesignPalette['--palette-text-primary'],
			bg: bridgeDesignPalette['--palette-neutral-n1'],
			colors: {
				'editor.background': bridgeDesignPalette['--palette-neutral-n1'],
				'editor.foreground': bridgeDesignPalette['--palette-text-primary'],
				'gitDecoration.addedResourceForeground': bridgeDesignPalette['--palette-green'],
				'gitDecoration.deletedResourceForeground': bridgeDesignPalette['--palette-red'],
				'gitDecoration.modifiedResourceForeground': bridgeDesignPalette['--palette-blue'],
			},
		});
		expect(bridgeGhosttyCatppuccinTreeStyles['--trees-theme-git-added-fg']).toBe(
			bridgeDesignPalette['--palette-green'],
		);
		expect(bridgeGhosttyCatppuccinTreeStyles['--trees-theme-git-deleted-fg']).toBe(
			bridgeDesignPalette['--palette-red'],
		);
		expect(bridgeGhosttyCatppuccinTreeStyles['--trees-theme-git-modified-fg']).toBe(
			bridgeDesignPalette['--palette-blue'],
		);
	});

	test('binds canonical tree roles and typography through installed override hooks', async () => {
		const installedTreeStyles = await readInstalledPackageStyle('@pierre/trees');

		expect(installedTreeStyles).toContain(
			'--trees-font-family: var(--trees-font-family-override, system-ui)',
		);
		expect(installedTreeStyles).toContain(
			'--trees-font-size: var(--trees-font-size-override, 13px)',
		);
		expect(bridgeViewerTreeStyle).toMatchObject({
			backgroundColor: 'var(--sidebar)',
			color: 'var(--foreground)',
			'--trees-bg-override': 'var(--sidebar)',
			'--trees-bg-muted-override': 'var(--muted)',
			'--trees-selected-bg-override': 'var(--selection)',
			'--trees-git-renamed-color-override': 'var(--primary)',
			'--trees-font-family-override': 'var(--font-sans)',
			'--trees-font-size-override': '12px',
		});
		expect(`${JSON.stringify(bridgeViewerTreeStyle)}${bridgeViewerTreeUnsafeCSS}`).not.toContain(
			'--bridge-',
		);
	});

	test('keeps installed Pierre code typography connected to the supplied host variables', async () => {
		const installedDiffStyles = await readInstalledPackageStyle('@pierre/diffs');

		expect(installedDiffStyles).toContain('font-size:var(--diffs-font-size,13px)');
		expect(installedDiffStyles).toContain(
			'font-family:var(--diffs-font-family,var(--diffs-font-fallback))',
		);
	});
});

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

async function readInstalledPackageStyle(
	packageName: '@pierre/diffs' | '@pierre/trees',
): Promise<string> {
	const packageEntryUrl = import.meta.resolve(packageName);
	return readFile(new URL('./style.js', packageEntryUrl), 'utf8');
}
