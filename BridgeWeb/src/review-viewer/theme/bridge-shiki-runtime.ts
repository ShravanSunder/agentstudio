import {
	createBundledHighlighter,
	createCssVariablesTheme,
	createSingletonShorthands,
	type DynamicImportLanguageRegistration,
	type DynamicImportThemeRegistration,
	getTokenStyleObject,
	guessEmbeddedLanguages,
	stringifyTokenStyle,
} from '@shikijs/core';
import {
	createJavaScriptRegexEngine,
	defaultJavaScriptRegexConstructor,
} from '@shikijs/engine-javascript';
import { createOnigurumaEngine, loadWasm } from '@shikijs/engine-oniguruma';

interface BridgeShikiLanguageDescriptor {
	readonly id: string;
	readonly import: DynamicImportLanguageRegistration;
	readonly aliases?: readonly string[];
}

const bridgeShikiLanguageDescriptors = [
	{
		id: 'typescript',
		import: (): ReturnType<DynamicImportLanguageRegistration> =>
			import('@shikijs/langs/typescript'),
		aliases: ['ts', 'mts', 'cts'],
	},
	{
		id: 'tsx',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/tsx'),
	},
	{
		id: 'javascript',
		import: (): ReturnType<DynamicImportLanguageRegistration> =>
			import('@shikijs/langs/javascript'),
		aliases: ['js', 'mjs', 'cjs'],
	},
	{
		id: 'jsx',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/jsx'),
	},
	{
		id: 'json',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/json'),
	},
	{
		id: 'jsonc',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/jsonc'),
	},
	{
		id: 'json5',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/json5'),
	},
	{
		id: 'jsonl',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/jsonl'),
	},
	{
		id: 'yaml',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/yaml'),
		aliases: ['yml'],
	},
	{
		id: 'toml',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/toml'),
	},
	{
		id: 'markdown',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/markdown'),
		aliases: ['md'],
	},
	{
		id: 'mdx',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/mdx'),
	},
	{
		id: 'diff',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/diff'),
	},
	{
		id: 'swift',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/swift'),
	},
	{
		id: 'bash',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/bash'),
	},
	{
		id: 'shellscript',
		import: (): ReturnType<DynamicImportLanguageRegistration> =>
			import('@shikijs/langs/shellscript'),
		aliases: ['sh', 'shell'],
	},
	{
		id: 'zsh',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/zsh'),
	},
	{
		id: 'fish',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/fish'),
	},
	{
		id: 'dockerfile',
		import: (): ReturnType<DynamicImportLanguageRegistration> =>
			import('@shikijs/langs/dockerfile'),
		aliases: ['docker'],
	},
	{
		id: 'makefile',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/makefile'),
		aliases: ['make'],
	},
	{
		id: 'cmake',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/cmake'),
	},
	{
		id: 'c',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/c'),
	},
	{
		id: 'cpp',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/cpp'),
		aliases: ['c++'],
	},
	{
		id: 'objective-c',
		import: (): ReturnType<DynamicImportLanguageRegistration> =>
			import('@shikijs/langs/objective-c'),
		aliases: ['objc'],
	},
	{
		id: 'objective-cpp',
		import: (): ReturnType<DynamicImportLanguageRegistration> =>
			import('@shikijs/langs/objective-cpp'),
	},
	{
		id: 'python',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/python'),
		aliases: ['py'],
	},
	{
		id: 'ruby',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/ruby'),
		aliases: ['rb'],
	},
	{
		id: 'go',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/go'),
	},
	{
		id: 'rust',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/rust'),
		aliases: ['rs'],
	},
	{
		id: 'java',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/java'),
	},
	{
		id: 'kotlin',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/kotlin'),
		aliases: ['kt'],
	},
	{
		id: 'csharp',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/csharp'),
		aliases: ['cs'],
	},
	{
		id: 'php',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/php'),
	},
	{
		id: 'html',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/html'),
	},
	{
		id: 'css',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/css'),
	},
	{
		id: 'scss',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/scss'),
	},
	{
		id: 'sass',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/sass'),
	},
	{
		id: 'less',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/less'),
	},
	{
		id: 'sql',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/sql'),
	},
	{
		id: 'xml',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/xml'),
	},
	{
		id: 'graphql',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/graphql'),
	},
	{
		id: 'protobuf',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/protobuf'),
		aliases: ['proto'],
	},
	{
		id: 'ini',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/ini'),
	},
	{
		id: 'dotenv',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/dotenv'),
	},
	{
		id: 'nix',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/nix'),
	},
	{
		id: 'hcl',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/hcl'),
	},
	{
		id: 'terraform',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/terraform'),
		aliases: ['tf', 'tfvars'],
	},
	{
		id: 'lua',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/lua'),
	},
	{
		id: 'perl',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/perl'),
	},
	{
		id: 'zig',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/zig'),
	},
	{
		id: 'wasm',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/wasm'),
		aliases: ['wat'],
	},
	{
		id: 'vue',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/vue'),
	},
	{
		id: 'svelte',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/svelte'),
	},
	{
		id: 'astro',
		import: (): ReturnType<DynamicImportLanguageRegistration> => import('@shikijs/langs/astro'),
	},
] satisfies readonly BridgeShikiLanguageDescriptor[];

export type BundledLanguage = string;
export type BundledTheme = string;

export const bundledLanguagesInfo = bridgeShikiLanguageDescriptors;

export const bundledLanguagesBase = Object.fromEntries(
	bridgeShikiLanguageDescriptors.map(
		(descriptor): readonly [string, DynamicImportLanguageRegistration] => [
			descriptor.id,
			descriptor.import,
		],
	),
) satisfies Record<string, DynamicImportLanguageRegistration>;

export const bundledLanguagesAlias = Object.fromEntries(
	bridgeShikiLanguageDescriptors.flatMap(
		(descriptor): readonly (readonly [string, DynamicImportLanguageRegistration])[] =>
			(descriptor.aliases ?? []).map(
				(alias): readonly [string, DynamicImportLanguageRegistration] => [alias, descriptor.import],
			),
	),
) satisfies Record<string, DynamicImportLanguageRegistration>;

export const bundledLanguages = {
	...bundledLanguagesBase,
	...bundledLanguagesAlias,
} satisfies Record<string, DynamicImportLanguageRegistration>;

export const bundledThemes = {} satisfies Record<string, DynamicImportThemeRegistration>;
export const bundledThemesInfo = [] satisfies readonly never[];

export const createHighlighter = createBundledHighlighter({
	langs: bundledLanguages,
	themes: bundledThemes,
	engine: (): ReturnType<typeof createJavaScriptRegexEngine> => createJavaScriptRegexEngine(),
});

const bridgeShikiSingletonShorthands = createSingletonShorthands(createHighlighter, {
	guessEmbeddedLanguages: (code, lang): string[] | undefined =>
		Array.from(guessEmbeddedLanguages(code, lang)),
});

export const codeToHtml = bridgeShikiSingletonShorthands.codeToHtml;

export {
	createCssVariablesTheme,
	createJavaScriptRegexEngine,
	createOnigurumaEngine,
	defaultJavaScriptRegexConstructor,
	getTokenStyleObject,
	loadWasm,
	stringifyTokenStyle,
};
