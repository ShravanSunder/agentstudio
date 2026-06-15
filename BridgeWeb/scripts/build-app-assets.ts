import { spawn } from 'node:child_process';
import type { Dirent } from 'node:fs';
import { copyFile, mkdir, readdir, readFile, rm, rmdir, writeFile } from 'node:fs/promises';
import { basename, extname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	appAssetManifestFileName,
	buildAppAssetManifest,
	createAppIndexHtml,
	formatAppAssetManifest,
	validatePackagedAppOutput,
} from './app-asset-contract.ts';

interface BuiltBundleAssets {
	readonly scripts: readonly string[];
	readonly styles: readonly string[];
}

const packageRootPath = fileURLToPath(new URL('../', import.meta.url));
const appDirectoryPath = fileURLToPath(
	new URL('../../Sources/AgentStudio/Resources/BridgeWeb/app/', import.meta.url),
);
const appAssetsDirectoryPath = join(appDirectoryPath, 'assets');
const appWorkersDirectoryPath = join(appDirectoryPath, 'workers');
const portableWorkerAssetPath = 'workers/pierre-diffs-worker-portable.js';

await resetGeneratedAppDirectory(appDirectoryPath);
await mkdir(appAssetsDirectoryPath, { recursive: true });
await mkdir(appWorkersDirectoryPath, { recursive: true });

await runCommand({
	command: 'pnpm',
	args: ['exec', 'tsdown', '--config', 'tsdown.config.ts'],
	cwd: packageRootPath,
});

const portableWorkerSourceUrl = await resolvePublicPackageAsset(
	'@pierre/diffs/worker/worker-portable.js',
);
await copyFile(
	fileURLToPath(portableWorkerSourceUrl),
	join(appDirectoryPath, portableWorkerAssetPath),
);
await normalizeGeneratedTextAssets(appDirectoryPath);

const builtAssets = await collectBuiltBundleAssets(appAssetsDirectoryPath);
const mainScriptPath = builtAssets.scripts[0];

if (mainScriptPath === undefined) {
	throw new Error('Expected packaged app JavaScript asset');
}

const stylePaths = builtAssets.styles;
const manifest = await buildAppAssetManifest({
	appDirectoryPath,
	mainScriptPath,
	stylePaths,
	workerAssets: [
		{
			kind: 'pierre-diffs-shiki',
			path: portableWorkerAssetPath,
			source: 'packagedAppAsset',
		},
	],
});
const indexHtml = createAppIndexHtml({
	mainScriptPath,
	stylePaths,
});

validatePackagedAppOutput({ indexHtml, manifest });

await writeFile(
	join(appDirectoryPath, appAssetManifestFileName),
	formatAppAssetManifest(manifest),
	'utf8',
);
await writeFile(join(appDirectoryPath, 'index.html'), indexHtml, 'utf8');

async function runCommand(props: {
	readonly command: string;
	readonly args: readonly string[];
	readonly cwd: string;
}): Promise<void> {
	await new Promise<void>((resolve, reject) => {
		const child = spawn(props.command, props.args, {
			cwd: props.cwd,
			stdio: 'inherit',
		});

		child.on('error', reject);
		child.on('exit', (code: number | null): void => {
			if (code === 0) {
				resolve();
				return;
			}

			reject(new Error(`${props.command} exited with ${code ?? 'unknown status'}`));
		});
	});
}

async function resetGeneratedAppDirectory(directoryPath: string): Promise<void> {
	await mkdir(directoryPath, { recursive: true });
	await removeDirectoryContents(directoryPath);
}

async function removeDirectoryContents(directoryPath: string): Promise<void> {
	const entries = await readdir(directoryPath, { withFileTypes: true });

	await Promise.all(
		entries.map((entry: Dirent): Promise<void> => removeDirectoryEntry(directoryPath, entry)),
	);
}

async function removeDirectoryEntry(directoryPath: string, entry: Dirent): Promise<void> {
	const entryPath = join(directoryPath, entry.name);

	if (entry.isDirectory()) {
		await removeDirectoryContents(entryPath);
		await rmdir(entryPath);
		return;
	}

	if (entry.isFile() || entry.isSymbolicLink()) {
		await rm(entryPath, { force: true });
	}
}

async function resolvePublicPackageAsset(packageExport: string): Promise<URL> {
	return new URL(import.meta.resolve(packageExport));
}

async function collectBuiltBundleAssets(directoryPath: string): Promise<BuiltBundleAssets> {
	const entries = await readdir(directoryPath, { withFileTypes: true });
	const files = entries
		.filter((entry: Dirent): boolean => entry.isFile())
		.map((entry: Dirent): string => entry.name)
		.toSorted();
	const scripts = files
		.filter((fileName: string): boolean => extname(fileName) === '.js')
		.map((fileName: string): string => relative(appDirectoryPath, join(directoryPath, fileName)));
	const styles = files
		.filter((fileName: string): boolean => extname(fileName) === '.css')
		.map((fileName: string): string => relative(appDirectoryPath, join(directoryPath, fileName)));

	if (scripts.length !== 1) {
		throw new Error(`Expected exactly one app JavaScript asset, found ${scripts.length}`);
	}

	const firstScript = scripts[0];

	if (firstScript === undefined) {
		throw new Error('Expected packaged app JavaScript asset');
	}

	await assertNoExternalRuntimeImports(join(directoryPath, basename(firstScript)));

	return { scripts, styles };
}

async function normalizeGeneratedTextAssets(directoryPath: string): Promise<void> {
	const entries = await readdir(directoryPath, { withFileTypes: true });
	const normalizedExtensions = new Set(['.css', '.html', '.js', '.json', '.map', '.svg']);

	await Promise.all(
		entries.map(async (entry: Dirent): Promise<void> => {
			const entryPath = join(directoryPath, entry.name);

			if (entry.isDirectory()) {
				await normalizeGeneratedTextAssets(entryPath);
				return;
			}

			if (!entry.isFile() || !normalizedExtensions.has(extname(entry.name))) {
				return;
			}

			const content = await readFile(entryPath, 'utf8');
			const normalizedContent = content.replace(/[ \t]+$/gm, '');

			if (normalizedContent !== content) {
				await writeFile(entryPath, normalizedContent, 'utf8');
			}
		}),
	);
}

async function assertNoExternalRuntimeImports(scriptPath: string): Promise<void> {
	const script = await readFile(scriptPath, 'utf8');

	if (/from\s*["'](?:react|react-dom|@pierre\/|zustand|zod)/u.test(script)) {
		throw new Error(`Packaged app script still imports runtime packages: ${scriptPath}`);
	}
}
