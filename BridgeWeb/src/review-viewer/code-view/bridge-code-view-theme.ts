import type { DiffsThemeNames } from '@pierre/diffs';
import { hasResolvedThemes, registerCustomCSSVariableTheme, resolveThemes } from '@pierre/diffs';

export const bridgePierreDarkThemeName = 'catppuccin-mocha' satisfies DiffsThemeNames;

export const bridgeCodeViewThemeVariableDefaults = {
	foreground: '#cdd6f4',
	background: '#000000',
	'ansi-black': '#11111b',
	'ansi-red': '#f38ba8',
	'ansi-green': '#a6e3a1',
	'ansi-yellow': '#f9e2af',
	'ansi-blue': '#89b4fa',
	'ansi-magenta': '#cba6f7',
	'ansi-cyan': '#89dceb',
	'ansi-white': '#cdd6f4',
	'ansi-bright-black': '#6c7086',
	'ansi-bright-red': '#eba0ac',
	'ansi-bright-green': '#a6e3a1',
	'ansi-bright-yellow': '#f9e2af',
	'ansi-bright-blue': '#89b4fa',
	'ansi-bright-magenta': '#cba6f7',
	'ansi-bright-cyan': '#94e2d5',
	'ansi-bright-white': '#f5e0dc',
	'token-link': '#89b4fa',
	'token-string': '#a6e3a1',
	'token-comment': '#6c7086',
	'token-constant': '#fab387',
	'token-keyword': '#cba6f7',
	'token-parameter': '#f9e2af',
	'token-function': '#89b4fa',
	'token-string-expression': '#94e2d5',
	'token-punctuation': '#bac2de',
	'token-inserted': '#a6e3a1',
	'token-deleted': '#f38ba8',
	'token-changed': '#f9e2af',
} satisfies Record<string, string>;

export interface BridgeCodeViewThemeResolver {
	readonly hasResolvedThemes: (themeNames: DiffsThemeNames[]) => boolean;
	readonly registerCustomCSSVariableTheme: (
		name: DiffsThemeNames,
		variableDefaults: Record<string, string>,
		fontStyle?: boolean,
	) => void;
	readonly resolveThemes: (themeNames: DiffsThemeNames[]) => Promise<readonly unknown[]>;
}

export interface EnsureBridgeCodeViewThemeResolvedProps {
	readonly resolver?: BridgeCodeViewThemeResolver;
}

const defaultBridgeCodeViewThemeResolver: BridgeCodeViewThemeResolver = {
	hasResolvedThemes,
	registerCustomCSSVariableTheme,
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

	resolver.registerCustomCSSVariableTheme(
		bridgePierreDarkThemeName,
		bridgeCodeViewThemeVariableDefaults,
		false,
	);

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
