import type { Dirent } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { basename, extname, join, relative } from 'node:path';

export interface BuiltBundleAssets {
	readonly mainScript: string;
	readonly auxiliaryScripts: readonly string[];
	readonly styles: readonly string[];
}

export interface CollectBuiltBundleAssetsProps {
	readonly appDirectoryPath: string;
	readonly assetsDirectoryPath: string;
	readonly entrypointName: string;
}

export async function collectBuiltBundleAssets(
	props: CollectBuiltBundleAssetsProps,
): Promise<BuiltBundleAssets> {
	const entries = await readdir(props.assetsDirectoryPath, { withFileTypes: true });
	const files = entries
		.filter((entry: Dirent): boolean => entry.isFile())
		.map((entry: Dirent): string => entry.name)
		.toSorted();
	const scriptPaths = files
		.filter((fileName: string): boolean => extname(fileName) === '.js')
		.map((fileName: string): string =>
			relative(props.appDirectoryPath, join(props.assetsDirectoryPath, fileName)),
		);
	const entrypointScriptPaths = scriptPaths.filter((scriptPath: string): boolean =>
		isEntrypointScriptPath(scriptPath, props.entrypointName),
	);

	if (entrypointScriptPaths.length !== 1) {
		throw new Error(
			`Expected exactly one ${props.entrypointName} JavaScript asset, found ${entrypointScriptPaths.length}`,
		);
	}

	const mainScript = entrypointScriptPaths[0];
	if (mainScript === undefined) {
		throw new Error('Expected packaged app JavaScript asset');
	}

	await Promise.all(
		scriptPaths.map(
			(scriptPath: string): Promise<void> =>
				assertNoExternalRuntimeImports(join(props.appDirectoryPath, scriptPath)),
		),
	);

	return {
		mainScript,
		auxiliaryScripts: scriptPaths.filter(
			(scriptPath: string): boolean => scriptPath !== mainScript,
		),
		styles: files
			.filter((fileName: string): boolean => extname(fileName) === '.css')
			.map((fileName: string): string =>
				relative(props.appDirectoryPath, join(props.assetsDirectoryPath, fileName)),
			),
	};
}

function isEntrypointScriptPath(scriptPath: string, entrypointName: string): boolean {
	const fileName = basename(scriptPath);
	return fileName === `${entrypointName}.js` || fileName.startsWith(`${entrypointName}-`);
}

async function assertNoExternalRuntimeImports(scriptPath: string): Promise<void> {
	const script = await readFile(scriptPath, 'utf8');

	if (/from\s*["'](?:react|react-dom|@pierre\/|zustand|zod)/u.test(script)) {
		throw new Error(`Packaged app script still imports runtime packages: ${scriptPath}`);
	}

	const externalUrlSource = String.raw`(?:https?:|//|data:|blob:|file:|agentstudio://(?!app/))`;
	const externalRuntimePatterns: readonly RegExp[] = [
		new RegExp(String.raw`\bimport\s*\(\s*["']${externalUrlSource}`, 'u'),
		new RegExp(String.raw`^\s*import\s+["']${externalUrlSource}`, 'mu'),
		new RegExp(String.raw`\bfrom\s*["']${externalUrlSource}`, 'u'),
		new RegExp(
			String.raw`\bnew\s+(?:Shared)?Worker\s*\(\s*(?:new\s+URL\s*\(\s*)?["']${externalUrlSource}`,
			'u',
		),
	];
	for (const pattern of externalRuntimePatterns) {
		if (pattern.test(script)) {
			throw new Error(`Packaged app script contains external runtime import: ${scriptPath}`);
		}
	}
}
