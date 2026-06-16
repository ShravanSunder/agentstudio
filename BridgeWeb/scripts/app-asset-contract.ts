import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

import ts from 'typescript';

export const appAssetManifestFileName = 'agentstudio-app-assets.json';

const schemaVersion = 1;
const devEntrypointReference = '/src/app/bridge-app-bootstrap.tsx';
const packagedWorkerShikiWasmImportPattern = /import\((["'])\.\/wasm-[A-Za-z0-9_-]+\.js\1\)/gu;
const packagedWorkerShikiWasmUnavailableExpression =
	'Promise.reject(new Error("AgentStudio BridgeWeb packages only the shiki-js worker highlighter"))';

export interface CreateAppIndexHtmlProps {
	readonly mainScriptPath: string;
	readonly stylePaths: readonly string[];
}

export interface BuildAppAssetManifestProps {
	readonly appDirectoryPath: string;
	readonly mainScriptPath: string;
	readonly auxiliaryScriptPaths: readonly string[];
	readonly stylePaths: readonly string[];
	readonly workerAssets: readonly WorkerAssetInput[];
}

export interface WorkerAssetInput {
	readonly kind: string;
	readonly path: string;
	readonly workerKind: AppWorkerKind;
	readonly source: 'packagedAppAsset';
}

export type AppWorkerKind = 'classicWorker' | 'moduleWorker';

export interface AppAssetRecord {
	readonly path: string;
	readonly bytes: number;
	readonly sha256: string;
}

export interface AppWorkerAssetRecord extends AppAssetRecord {
	readonly kind: string;
	readonly source: 'packagedAppAsset';
	readonly agentStudioAppUrl: string;
	readonly workerKind: AppWorkerKind;
}

export interface AppAssetManifest {
	readonly schemaVersion: 1;
	readonly entrypoints: {
		readonly mainScript: AppAssetRecord;
		readonly auxiliaryScripts: readonly AppAssetRecord[];
		readonly styles: readonly AppAssetRecord[];
	};
	readonly workers: readonly AppWorkerAssetRecord[];
}

export interface ReadDependencyLicenseMetadataProps {
	readonly packageRootPath: string;
	readonly packageNames: readonly string[];
}

export interface DependencyLicenseMetadata {
	readonly name: string;
	readonly requestedVersion: string;
	readonly installedVersion: string;
	readonly license: string;
}

export interface ValidatePackagedAppOutputProps {
	readonly indexHtml: string;
	readonly manifest: AppAssetManifest;
}

export interface WorkerSourceSelfContainmentCheck {
	readonly isSelfContained: true;
	readonly checkedPatterns: readonly string[];
}

interface CreateAssetRecordProps {
	readonly appDirectoryPath: string;
	readonly assetPath: string;
}

export function createAppIndexHtml(props: CreateAppIndexHtmlProps): string {
	const normalizedScriptPath = normalizeAssetPath(props.mainScriptPath);
	const styleTags = props.stylePaths
		.map((stylePath: string): string => {
			const normalizedStylePath = normalizeAssetPath(stylePath);
			return `\t\t<link rel="stylesheet" href="./${normalizedStylePath}">`;
		})
		.join('\n');
	const styleBlock = styleTags.length > 0 ? `${styleTags}\n` : '';

	return `<!doctype html>
<html lang="en">
\t<head>
\t\t<meta charset="UTF-8">
\t\t<meta name="viewport" content="width=device-width, initial-scale=1.0">
${styleBlock}\t\t<title>AgentStudio Bridge</title>
\t</head>
\t<body>
\t\t<div id="root"></div>
\t\t<script type="module" src="./${normalizedScriptPath}"></script>
\t</body>
</html>
`;
}

export async function buildAppAssetManifest(
	props: BuildAppAssetManifestProps,
): Promise<AppAssetManifest> {
	return {
		schemaVersion,
		entrypoints: {
			mainScript: await createAssetRecord({
				appDirectoryPath: props.appDirectoryPath,
				assetPath: props.mainScriptPath,
			}),
			auxiliaryScripts: await Promise.all(
				props.auxiliaryScriptPaths.map(
					(auxiliaryScriptPath: string): Promise<AppAssetRecord> =>
						createAssetRecord({
							appDirectoryPath: props.appDirectoryPath,
							assetPath: auxiliaryScriptPath,
						}),
				),
			),
			styles: await Promise.all(
				props.stylePaths.map(
					(stylePath: string): Promise<AppAssetRecord> =>
						createAssetRecord({
							appDirectoryPath: props.appDirectoryPath,
							assetPath: stylePath,
						}),
				),
			),
		},
		workers: await Promise.all(
			props.workerAssets.map(
				async (workerAsset: WorkerAssetInput): Promise<AppWorkerAssetRecord> => ({
					kind: workerAsset.kind,
					source: workerAsset.source,
					agentStudioAppUrl: agentStudioAppUrlForAssetPath(workerAsset.path),
					workerKind: workerAsset.workerKind,
					...(await createAssetRecord({
						appDirectoryPath: props.appDirectoryPath,
						assetPath: workerAsset.path,
					})),
				}),
			),
		),
	};
}

export function parseAppAssetManifest(value: unknown): AppAssetManifest {
	if (!isRecord(value)) {
		throw new Error('App asset manifest must be an object');
	}

	const entrypoints = value['entrypoints'];
	const workers = value['workers'];

	if (
		value['schemaVersion'] !== schemaVersion ||
		!isRecord(entrypoints) ||
		!Array.isArray(workers)
	) {
		throw new Error('Invalid app asset manifest shape');
	}

	const mainScript = parseAssetRecord(entrypoints['mainScript']);
	const auxiliaryScripts = parseAssetRecordArray(entrypoints['auxiliaryScripts']);
	const styles = parseAssetRecordArray(entrypoints['styles']);

	return {
		schemaVersion,
		entrypoints: {
			mainScript,
			auxiliaryScripts,
			styles,
		},
		workers: workers.map((worker: unknown): AppWorkerAssetRecord => parseWorkerAssetRecord(worker)),
	};
}

export function formatAppAssetManifest(manifest: AppAssetManifest): string {
	return `${JSON.stringify(manifest, null, '\t')}\n`;
}

export async function readDependencyLicenseMetadata(
	props: ReadDependencyLicenseMetadataProps,
): Promise<readonly DependencyLicenseMetadata[]> {
	const rootPackageJson = await readJsonRecord(join(props.packageRootPath, 'package.json'));
	const dependencies = readStringRecord(rootPackageJson['dependencies']);
	const devDependencies = readStringRecord(rootPackageJson['devDependencies']);

	return Promise.all(
		props.packageNames.map(async (packageName: string): Promise<DependencyLicenseMetadata> => {
			const installedPackageJson = await readJsonRecord(
				join(props.packageRootPath, 'node_modules', packageName, 'package.json'),
			);
			const requestedVersion = dependencies[packageName] ?? devDependencies[packageName] ?? null;
			const installedVersion = installedPackageJson['version'];
			const license = installedPackageJson['license'];

			if (requestedVersion === null) {
				throw new Error(`Dependency is not declared in package.json: ${packageName}`);
			}

			if (typeof license !== 'string' || license === '') {
				throw new Error(`Dependency is missing license metadata: ${packageName}`);
			}

			if (typeof installedVersion !== 'string' || installedVersion === '') {
				throw new Error(`Dependency is missing version metadata: ${packageName}`);
			}

			return {
				name: packageName,
				requestedVersion,
				installedVersion,
				license,
			};
		}),
	);
}

export function validatePackagedAppOutput(props: ValidatePackagedAppOutputProps): void {
	if (props.indexHtml.includes(devEntrypointReference)) {
		throw new Error('Packaged app HTML must not reference the dev entrypoint');
	}

	if (!props.manifest.entrypoints.mainScript.path.endsWith('.js')) {
		throw new Error('Packaged app manifest is missing a JavaScript entrypoint');
	}

	if (props.manifest.workers.length === 0) {
		throw new Error('Packaged app manifest is missing a worker asset');
	}

	for (const asset of [
		props.manifest.entrypoints.mainScript,
		...props.manifest.entrypoints.auxiliaryScripts,
		...props.manifest.entrypoints.styles,
		...props.manifest.workers,
	]) {
		validateAssetRecord(asset);
	}
}

export function validateWorkerSourceSelfContained(
	workerSource: string,
): WorkerSourceSelfContainmentCheck {
	const checkedPatterns: readonly string[] = [
		'static import/export',
		'dynamic import(...)',
		'importScripts(...)',
		'fetch(...)',
		'new URL(<relative-or-external-literal>)',
		'new XMLHttpRequest(...)',
	];
	const sourceFile = ts.createSourceFile(
		'packaged-worker.js',
		workerSource,
		ts.ScriptTarget.ES2022,
		true,
		ts.ScriptKind.JS,
	);

	visitWorkerSourceNode(sourceFile, sourceFile);

	return {
		isSelfContained: true,
		checkedPatterns,
	};
}

export function normalizePackagedPierreWorkerSource(workerSource: string): string {
	return workerSource.replace(
		packagedWorkerShikiWasmImportPattern,
		packagedWorkerShikiWasmUnavailableExpression,
	);
}

async function createAssetRecord(props: CreateAssetRecordProps): Promise<AppAssetRecord> {
	const normalizedAssetPath = normalizeAssetPath(props.assetPath);
	const content = await readFile(join(props.appDirectoryPath, normalizedAssetPath));

	return {
		path: normalizedAssetPath,
		bytes: content.byteLength,
		sha256: createHash('sha256').update(content).digest('hex'),
	};
}

function normalizeAssetPath(assetPath: string): string {
	const normalizedAssetPath = assetPath.replaceAll('\\', '/');

	if (normalizedAssetPath.startsWith('/') || normalizedAssetPath.includes('../')) {
		throw new Error(`Packaged app asset path must be relative: ${assetPath}`);
	}

	return normalizedAssetPath;
}

function visitWorkerSourceNode(sourceFile: ts.SourceFile, node: ts.Node): void {
	if (ts.isImportDeclaration(node)) {
		throwWorkerSelfContainmentError(sourceFile, node, 'static import');
	}

	if (ts.isExportDeclaration(node) && node.moduleSpecifier !== undefined) {
		throwWorkerSelfContainmentError(sourceFile, node, 're-export from another module');
	}

	if (ts.isCallExpression(node)) {
		if (node.expression.kind === ts.SyntaxKind.ImportKeyword) {
			throwWorkerSelfContainmentError(sourceFile, node, 'dynamic import(...)');
		}

		if (isIdentifierExpression(node.expression, 'importScripts')) {
			throwWorkerSelfContainmentError(sourceFile, node, 'importScripts(...)');
		}

		if (isIdentifierExpression(node.expression, 'fetch')) {
			throwWorkerSelfContainmentError(sourceFile, node, 'fetch(...)');
		}
	}

	if (ts.isNewExpression(node)) {
		if (
			isIdentifierExpression(node.expression, 'URL') &&
			isRelativeOrExternalLiteral(node.arguments?.[0])
		) {
			throwWorkerSelfContainmentError(sourceFile, node, 'new URL(<relative-or-external-literal>)');
		}

		if (isIdentifierExpression(node.expression, 'XMLHttpRequest')) {
			throwWorkerSelfContainmentError(sourceFile, node, 'new XMLHttpRequest(...)');
		}
	}

	ts.forEachChild(node, (child: ts.Node): void => {
		visitWorkerSourceNode(sourceFile, child);
	});
}

function isIdentifierExpression(expression: ts.Expression, identifierText: string): boolean {
	return ts.isIdentifier(expression) && expression.text === identifierText;
}

function isRelativeOrExternalLiteral(node: ts.Node | undefined): boolean {
	if (node === undefined) {
		return false;
	}
	if (!ts.isStringLiteral(node) && !ts.isNoSubstitutionTemplateLiteral(node)) {
		return false;
	}
	return /^(?:\.{0,2}\/|https?:|\/\/|data:|blob:|file:|agentstudio:\/\/(?!app\/))/u.test(node.text);
}

function throwWorkerSelfContainmentError(
	sourceFile: ts.SourceFile,
	node: ts.Node,
	description: string,
): never {
	const position = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
	throw new Error(
		`Packaged worker source must be self-contained; found ${description} at ${
			position.line + 1
		}:${position.character + 1}`,
	);
}

async function readJsonRecord(filePath: string): Promise<Record<string, unknown>> {
	const parsed: unknown = JSON.parse(await readFile(filePath, 'utf8'));

	if (!isRecord(parsed)) {
		throw new Error(`Expected JSON object: ${filePath}`);
	}

	return parsed;
}

function parseAssetRecord(value: unknown): AppAssetRecord {
	if (!isRecord(value)) {
		throw new Error('Expected asset record object');
	}

	const path = value['path'];
	const bytes = value['bytes'];
	const sha256 = value['sha256'];

	if (typeof path !== 'string' || typeof bytes !== 'number' || typeof sha256 !== 'string') {
		throw new Error('Invalid asset record shape');
	}

	return { path, bytes, sha256 };
}

function parseAssetRecordArray(value: unknown): readonly AppAssetRecord[] {
	if (!Array.isArray(value)) {
		throw new Error('Expected asset record array');
	}

	return value.map((asset: unknown): AppAssetRecord => parseAssetRecord(asset));
}

function parseWorkerAssetRecord(value: unknown): AppWorkerAssetRecord {
	const asset = parseAssetRecord(value);

	if (!isRecord(value)) {
		throw new Error('Expected worker asset record object');
	}

	const kind = value['kind'];
	const source = value['source'];
	const agentStudioAppUrl = value['agentStudioAppUrl'];
	const workerKind = value['workerKind'];

	if (
		typeof kind !== 'string' ||
		source !== 'packagedAppAsset' ||
		typeof agentStudioAppUrl !== 'string' ||
		!agentStudioAppUrl.startsWith('agentstudio://app/') ||
		(workerKind !== 'classicWorker' && workerKind !== 'moduleWorker')
	) {
		throw new Error('Invalid worker asset record shape');
	}

	return {
		...asset,
		kind,
		source,
		agentStudioAppUrl,
		workerKind,
	};
}

function agentStudioAppUrlForAssetPath(assetPath: string): string {
	return `agentstudio://app/${normalizeAssetPath(assetPath)}`;
}

function readStringRecord(value: unknown): Record<string, string> {
	if (!isRecord(value)) {
		return {};
	}

	return Object.fromEntries(
		Object.entries(value).filter(
			(entry): entry is [string, string] => typeof entry[1] === 'string',
		),
	);
}

function validateAssetRecord(asset: AppAssetRecord): void {
	normalizeAssetPath(asset.path);

	if (!Number.isInteger(asset.bytes) || asset.bytes <= 0) {
		throw new Error(`Packaged app asset has invalid byte size: ${asset.path}`);
	}

	if (!/^[a-f0-9]{64}$/.test(asset.sha256)) {
		throw new Error(`Packaged app asset has invalid sha256: ${asset.path}`);
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
