import type { DiffsThemeNames } from '@pierre/diffs';
import { hasResolvedThemes, registerCustomTheme, resolveThemes } from '@pierre/diffs';
import catppuccinMochaTheme from '@shikijs/themes/catppuccin-mocha';

export const bridgePierreDarkThemeName = 'agentstudio-ghostty-dark' satisfies DiffsThemeNames;

const bridgePierreDarkTheme = {
	...catppuccinMochaTheme,
	name: bridgePierreDarkThemeName,
	displayName: 'Agent Studio Ghostty Dark',
	colors: {
		...catppuccinMochaTheme.colors,
		'editor.background': '#282C34',
		'editor.foreground': '#FFFFFF',
		'editorCursor.background': '#282C34',
	},
};

export interface BridgeCodeViewThemeResolver {
	readonly hasResolvedThemes: (themeNames: DiffsThemeNames[]) => boolean;
	readonly resolveThemes: (themeNames: DiffsThemeNames[]) => Promise<readonly unknown[]>;
}

export interface EnsureBridgeCodeViewThemeResolvedProps {
	readonly resolver?: BridgeCodeViewThemeResolver;
}

const defaultBridgeCodeViewThemeResolver: BridgeCodeViewThemeResolver = {
	hasResolvedThemes,
	resolveThemes,
};

let defaultThemeResolutionPromise: Promise<void> | null = null;
let didRegisterBridgeCodeViewThemes = false;

export async function ensureBridgeCodeViewThemeResolved(
	props: EnsureBridgeCodeViewThemeResolvedProps = {},
): Promise<void> {
	const resolver = props.resolver ?? defaultBridgeCodeViewThemeResolver;
	const themeNames = makeBridgeCodeViewThemeNames();

	if (resolver.hasResolvedThemes(themeNames)) {
		return;
	}

	if (resolver !== defaultBridgeCodeViewThemeResolver) {
		await resolver.resolveThemes(themeNames);
		return;
	}

	defaultThemeResolutionPromise ??= resolver
		.resolveThemes(themeNames)
		.then((): void => {})
		.catch((error: unknown): never => {
			defaultThemeResolutionPromise = null;
			throw error;
		});
	await defaultThemeResolutionPromise;
}

export function registerBridgeCodeViewThemes(): void {
	if (didRegisterBridgeCodeViewThemes) {
		return;
	}
	didRegisterBridgeCodeViewThemes = true;
	registerCustomTheme(bridgePierreDarkThemeName, () => Promise.resolve(bridgePierreDarkTheme));
}

function makeBridgeCodeViewThemeNames(): DiffsThemeNames[] {
	registerBridgeCodeViewThemes();
	return [bridgePierreDarkThemeName];
}

// CodeView options can be consumed before the worker-pool provider effect runs.
// Register during module evaluation so every main-thread Pierre renderer can
// resolve the custom name before its first asynchronous highlight begins.
registerBridgeCodeViewThemes();
