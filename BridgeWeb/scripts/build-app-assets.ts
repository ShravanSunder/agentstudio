import { spawn } from 'node:child_process';
import type { Dirent } from 'node:fs';
import { copyFile, mkdir, readdir, readFile, rm, rmdir, writeFile } from 'node:fs/promises';
import { basename, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	appAssetManifestFileName,
	buildAppAssetManifest,
	createAppIndexHtml,
	formatAppAssetManifest,
	normalizePackagedPierreWorkerSource,
	validatePackagedAppOutput,
} from './app-asset-contract.ts';
import { collectBuiltBundleAssets } from './build-app-assets-collector.ts';
import { withBridgeWebAppBuildLock } from './build-app-assets-lock.ts';

const packageRootPath = fileURLToPath(new URL('../', import.meta.url));
const appDirectoryPath = fileURLToPath(
	new URL('../../Sources/AgentStudio/Resources/BridgeWeb/app/', import.meta.url),
);
const appAssetsDirectoryPath = join(appDirectoryPath, 'assets');
const appWorkersDirectoryPath = join(appDirectoryPath, 'workers');
const bridgeAppCssSourcePath = join(packageRootPath, 'src/app/bridge-app.css');
const bridgeAppCssAssetPath = join(appAssetsDirectoryPath, 'bridge-app.css');
const portableWorkerAssetPath = 'workers/pierre-diffs-worker-portable.js';

const runBuildAppAssets = async (): Promise<void> => {
	await resetGeneratedAppDirectory(appDirectoryPath);
	await mkdir(appAssetsDirectoryPath, { recursive: true });
	await mkdir(appWorkersDirectoryPath, { recursive: true });

	await runCommand({
		command: 'pnpm',
		args: ['exec', 'tsdown', '--config', 'tsdown.config.ts'],
		cwd: packageRootPath,
	});
	await removeGeneratedStyleAssets(appAssetsDirectoryPath);
	await runCommand({
		command: 'pnpm',
		args: [
			'exec',
			'tailwindcss',
			'--input',
			bridgeAppCssSourcePath,
			'--output',
			bridgeAppCssAssetPath,
			'--minify',
		],
		cwd: packageRootPath,
	});

	const portableWorkerSourceUrl = await resolvePublicPackageAsset(
		'@pierre/diffs/worker/worker-portable.js',
	);
	await copyFile(
		fileURLToPath(portableWorkerSourceUrl),
		join(appDirectoryPath, portableWorkerAssetPath),
	);
	await normalizePackagedPierreWorker(join(appDirectoryPath, portableWorkerAssetPath));
	await normalizeGeneratedTextAssets(appDirectoryPath);

	const builtAssets = await collectBuiltBundleAssets({
		appDirectoryPath,
		assetsDirectoryPath: appAssetsDirectoryPath,
		entrypointName: 'bridge-app',
	});
	const mainScriptPath = builtAssets.mainScript;
	const stylePaths = builtAssets.styles;
	const markdownWorkerAssetPath = requiredAuxiliaryScriptPath({
		auxiliaryScriptPaths: builtAssets.auxiliaryScripts,
		entrypointName: 'bridge-markdown-render-worker',
	});
	const projectionWorkerAssetPath = requiredAuxiliaryScriptPath({
		auxiliaryScriptPaths: builtAssets.auxiliaryScripts,
		entrypointName: 'review-projection-worker',
	});
	const workerFetchProbeAssetPath = requiredAuxiliaryScriptPath({
		auxiliaryScriptPaths: builtAssets.auxiliaryScripts,
		entrypointName: 'bridge-worker-fetch-probe-worker',
	});
	void workerFetchProbeAssetPath;
	const bridgeCommWorkerAssetPath = requiredAuxiliaryScriptPath({
		auxiliaryScriptPaths: builtAssets.auxiliaryScripts,
		entrypointName: 'bridge-comm-worker',
	});
	const manifest = await buildAppAssetManifest({
		appDirectoryPath,
		mainScriptPath,
		auxiliaryScriptPaths: builtAssets.auxiliaryScripts,
		stylePaths,
		workerAssets: [
			{
				kind: 'pierre-diffs-shiki',
				path: portableWorkerAssetPath,
				workerKind: 'classicWorker',
				source: 'packagedAppAsset',
			},
			{
				kind: 'bridge-markdown-render',
				path: markdownWorkerAssetPath,
				workerKind: 'moduleWorker',
				source: 'packagedAppAsset',
			},
			{
				kind: 'bridge-review-projection',
				path: projectionWorkerAssetPath,
				workerKind: 'moduleWorker',
				source: 'packagedAppAsset',
			},
			{
				kind: 'bridge-comm-worker',
				path: bridgeCommWorkerAssetPath,
				workerKind: 'moduleWorker',
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
};

if (process.env['BRIDGE_WEB_APP_BUILD_LOCK_HELD'] === '1') {
	await runBuildAppAssets();
} else {
	await withBridgeWebAppBuildLock(runBuildAppAssets);
}

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

async function removeGeneratedStyleAssets(directoryPath: string): Promise<void> {
	const entries = await readdir(directoryPath, { withFileTypes: true });

	await Promise.all(
		entries.map(async (entry: Dirent): Promise<void> => {
			if (!entry.isFile() || extname(entry.name) !== '.css') {
				return;
			}
			await rm(join(directoryPath, entry.name), { force: true });
		}),
	);
}

async function resolvePublicPackageAsset(packageExport: string): Promise<URL> {
	return new URL(import.meta.resolve(packageExport));
}

function requiredAuxiliaryScriptPath(props: {
	readonly auxiliaryScriptPaths: readonly string[];
	readonly entrypointName: string;
}): string {
	const exactMatches = props.auxiliaryScriptPaths.filter(
		(scriptPath: string): boolean => basename(scriptPath) === `${props.entrypointName}.js`,
	);
	const matches =
		exactMatches.length > 0
			? exactMatches
			: props.auxiliaryScriptPaths.filter((scriptPath: string): boolean => {
					const fileName = basename(scriptPath);
					return fileName.startsWith(`${props.entrypointName}-`);
				});
	if (matches.length !== 1) {
		throw new Error(
			`Expected exactly one ${props.entrypointName} JavaScript asset, found ${matches.length}`,
		);
	}
	const match = matches[0];
	if (match === undefined) {
		throw new Error(`Expected generated ${props.entrypointName} asset`);
	}
	return match;
}

async function normalizePackagedPierreWorker(workerPath: string): Promise<void> {
	const workerSource = await readFile(workerPath, 'utf8');
	const normalizedWorkerSource = normalizePackagedPierreWorkerSource(workerSource);

	if (normalizedWorkerSource !== workerSource) {
		await writeFile(workerPath, normalizedWorkerSource, 'utf8');
	}
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
