import { execFile } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import {
	type AppAssetManifest,
	appAssetManifestFileName,
	parseAppAssetManifest,
	readDependencyLicenseMetadata,
	summarizeAppAssetTotals,
	validatePackagedAppAssetContents,
	validatePackagedAppOutput,
	validateWorkerSourceSelfContained,
	type WorkerSourceSelfContainmentCheck,
} from './app-asset-contract.ts';

interface GitIdentity {
	readonly commit: string;
	readonly branch: string;
}

const execFileAsync = promisify(execFile);

const packageRootPath = fileURLToPath(new URL('../', import.meta.url));
const repoRootPath = fileURLToPath(new URL('../../', import.meta.url));
const appDirectoryPath = join(repoRootPath, 'Sources/AgentStudio/Resources/BridgeWeb/app');
const proofDirectoryPath = join(repoRootPath, 'tmp/bridge-web-assets');
const proofFilePath = join(proofDirectoryPath, 'latest-app-asset-audit.json');

const auditToolDependencyNames = ['@tailwindcss/cli', '@tsdown/css', 'tailwindcss', 'tsdown'];

const manifest = parseAppAssetManifest(
	JSON.parse(await readFile(join(appDirectoryPath, appAssetManifestFileName), 'utf8')),
);
const indexHtml = await readFile(join(appDirectoryPath, 'index.html'), 'utf8');

validatePackagedAppOutput({ indexHtml, manifest });
await validatePackagedAppAssetContents({ appDirectoryPath, manifest });

const dependencies = await readDependencyLicenseMetadata({
	packageRootPath,
	packageNames: await readAuditedDependencyNames(),
});
const assetTotals = summarizeAppAssetTotals(manifest);
const workerSelfContainmentChecks = await readWorkerSelfContainmentChecks(manifest);
const git = await readGitIdentity();
const audit = {
	schemaVersion: 1,
	git,
	dependencies,
	assetTotals,
	workerSelfContainmentChecks,
	manifest,
};

await mkdir(proofDirectoryPath, { recursive: true });
await writeFile(proofFilePath, `${JSON.stringify(audit, null, '\t')}\n`, 'utf8');

console.log(`[bridge-web-audit] wrote ${proofFilePath}`);
console.log(`[bridge-web-audit] dependencies=${dependencies.length}`);
console.log(`[bridge-web-audit] totalBytes=${assetTotals.totalBytes}`);

async function readWorkerSelfContainmentChecks(
	assetManifest: AppAssetManifest,
): Promise<Readonly<Record<string, WorkerSourceSelfContainmentCheck>>> {
	const checks = await Promise.all(
		assetManifest.workers.map(
			async (worker): Promise<readonly [string, WorkerSourceSelfContainmentCheck]> => {
				const workerSource = await readFile(join(appDirectoryPath, worker.path), 'utf8');
				return [worker.path, validateWorkerSourceSelfContained(workerSource)];
			},
		),
	);
	return Object.fromEntries(checks);
}

async function readAuditedDependencyNames(): Promise<readonly string[]> {
	const packageJson = JSON.parse(await readFile(join(packageRootPath, 'package.json'), 'utf8'));
	const packageDependencies = packageJson['dependencies'];
	if (
		typeof packageDependencies !== 'object' ||
		packageDependencies === null ||
		Array.isArray(packageDependencies)
	) {
		throw new Error('BridgeWeb package.json dependencies must be an object');
	}

	return [
		...new Set([...Object.keys(packageDependencies), ...auditToolDependencyNames]),
	].toSorted();
}

async function readGitIdentity(): Promise<GitIdentity> {
	return {
		commit: await execGit(['rev-parse', 'HEAD']),
		branch: await execGit(['rev-parse', '--abbrev-ref', 'HEAD']),
	};
}

async function execGit(args: readonly string[]): Promise<string> {
	const { stdout } = await execFileAsync('git', args, { cwd: repoRootPath });
	return stdout.trim();
}
