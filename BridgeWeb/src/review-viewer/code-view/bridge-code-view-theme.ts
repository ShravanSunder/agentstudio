import type { DiffsThemeNames } from '@pierre/diffs';
import { hasResolvedThemes, registerCustomTheme, resolveThemes } from '@pierre/diffs';
import catppuccinMochaTheme from '@shikijs/themes/catppuccin-mocha';

export const bridgePierreDarkThemeName = 'catppuccin-mocha' satisfies DiffsThemeNames;

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
	registerCustomTheme(bridgePierreDarkThemeName, () => Promise.resolve(catppuccinMochaTheme));
}

function makeBridgeCodeViewThemeNames(): DiffsThemeNames[] {
	registerBridgeCodeViewThemes();
	return [bridgePierreDarkThemeName];
}
