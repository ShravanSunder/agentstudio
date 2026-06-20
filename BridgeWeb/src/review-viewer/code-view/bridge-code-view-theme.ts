import type { DiffsThemeNames } from '@pierre/diffs';
import { hasResolvedThemes, resolveThemes } from '@pierre/diffs';

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

function makeBridgeCodeViewThemeNames(): DiffsThemeNames[] {
	return [bridgePierreDarkThemeName];
}
