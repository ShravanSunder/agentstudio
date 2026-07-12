import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

import ts from 'typescript';

import { validateNoDevOnlyBridgeWebReferences } from './packaged-app-asset-content-contract.ts';
export {
	validatePackagedAppAssetContents,
	type ValidatePackagedAppAssetContentsProps,
} from './packaged-app-asset-content-contract.ts';

export const appAssetManifestFileName = 'agentstudio-app-assets.json';

const schemaVersion = 1;
const legacyDevEntrypointReference = '/src/app/bridge-app-bootstrap.tsx';
const packagedWorkerShikiWasmImportPattern = /import\((["'])\.\/wasm-[A-Za-z0-9_-]+\.js\1\)/gu;
const packagedWorkerShikiWasmUnavailableExpression =
	'Promise.reject(new Error("AgentStudio BridgeWeb packages only the shiki-js worker highlighter"))';
const bridgeCommWorkerAssetKind = 'bridge-comm-worker';
const bridgeProductCapabilityHeaderName = 'X-AgentStudio-Bridge-Product-Capability';
const bridgeProductContentTypeHeaderName = 'Content-Type';
const bridgeProductContentType = 'application/json';
const bridgeProductRequestMethod = 'POST';
const bridgeProductRoutes = new Set([
	'agentstudio://rpc/command',
	'agentstudio://rpc/stream',
	'agentstudio://rpc/content',
]);

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

export interface AppAssetTotals {
	readonly appBytes: number;
	readonly workerBytes: number;
	readonly totalBytes: number;
	readonly appAssetCount: number;
	readonly workerAssetCount: number;
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

export interface ValidateWorkerSourceSelfContainedProps {
	readonly workerAssetKind: string;
	readonly workerSource: string;
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

export function summarizeAppAssetTotals(assetManifest: AppAssetManifest): AppAssetTotals {
	const appAssets = [
		assetManifest.entrypoints.mainScript,
		...assetManifest.entrypoints.auxiliaryScripts,
		...assetManifest.entrypoints.styles,
	];
	const workerAssets = assetManifest.workers;
	const appBytes = sumAssetBytes(appAssets);
	const workerBytes = sumAssetBytes(workerAssets);
	const uniqueAssets = new Map<string, AppAssetRecord>();

	for (const asset of [...appAssets, ...workerAssets]) {
		uniqueAssets.set(asset.path, asset);
	}

	return {
		appBytes,
		workerBytes,
		totalBytes: sumAssetBytes([...uniqueAssets.values()]),
		appAssetCount: appAssets.length,
		workerAssetCount: workerAssets.length,
	};
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
	if (props.indexHtml.includes(legacyDevEntrypointReference)) {
		throw new Error('Packaged app HTML must not reference the dev entrypoint');
	}

	validateNoDevOnlyBridgeWebReferences(props.indexHtml);

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
		validateNoDevOnlyBridgeWebReferences(asset.path);
	}
}

export function validateWorkerSourceSelfContained(
	props: ValidateWorkerSourceSelfContainedProps,
): WorkerSourceSelfContainmentCheck {
	const checkedPatterns: readonly string[] = [
		'static import/export',
		'dynamic import(...)',
		'importScripts(...)',
		'fetch(...) absent except exact bridge product POST carriers',
		'new URL(<relative-or-external-literal>)',
		'new XMLHttpRequest(...)',
	];
	const workerSourceAnalysis = createWorkerSourceAnalysis(props.workerSource);

	visitWorkerSourceNode({
		node: workerSourceAnalysis.sourceFile,
		workerSourceAnalysis,
		workerAssetKind: props.workerAssetKind,
	});

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

interface VisitWorkerSourceNodeProps {
	readonly node: ts.Node;
	readonly workerSourceAnalysis: WorkerSourceAnalysis;
	readonly workerAssetKind: string;
}

function visitWorkerSourceNode(props: VisitWorkerSourceNodeProps): void {
	const { node, workerSourceAnalysis } = props;
	const { sourceFile } = workerSourceAnalysis;
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

		if (isGlobalFetchExpression(node.expression, workerSourceAnalysis)) {
			validateWorkerFetchCall({
				fetchCall: node,
				sourceFile,
				workerAssetKind: props.workerAssetKind,
			});
		}
	}

	if (
		ts.isExpression(node) &&
		isGlobalFetchExpression(node, workerSourceAnalysis) &&
		!isDirectCallCallee(node)
	) {
		throwWorkerSelfContainmentError(sourceFile, node, 'indirect global fetch reference');
	}

	if (ts.isIdentifier(node) && isAmbiguousLocalFetchReference(node, workerSourceAnalysis)) {
		throwWorkerSelfContainmentError(sourceFile, node, 'ambiguous local fetch alias');
	}

	if (ts.isBindingElement(node) && isGlobalFetchBindingElement(node, workerSourceAnalysis)) {
		throwWorkerSelfContainmentError(sourceFile, node, 'global fetch destructuring');
	}

	if (
		ts.isElementAccessExpression(node) &&
		stringLiteralValue(node.argumentExpression) === null &&
		isGlobalObjectExpression({
			expression: node.expression,
			...workerSourceAnalysis,
		})
	) {
		throwWorkerSelfContainmentError(sourceFile, node, 'ambiguous global object property access');
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

	ts.forEachChild(node, (child: ts.Node): void => visitWorkerSourceNode({ ...props, node: child }));
}

interface WorkerSourceAnalysis {
	readonly checker: ts.TypeChecker;
	readonly globalObjectAliasSymbols: ReadonlySet<ts.Symbol>;
	readonly sourceFile: ts.SourceFile;
}

function createWorkerSourceAnalysis(workerSource: string): WorkerSourceAnalysis {
	const sourceFileName = 'packaged-worker.js';
	const compilerOptions = {
		allowJs: true,
		module: ts.ModuleKind.ESNext,
		noLib: true,
		target: ts.ScriptTarget.ES2022,
	} satisfies ts.CompilerOptions;
	const sourceFile = ts.createSourceFile(
		sourceFileName,
		workerSource,
		compilerOptions.target,
		true,
		ts.ScriptKind.JS,
	);
	const compilerHost = ts.createCompilerHost(compilerOptions);
	compilerHost.fileExists = (fileName: string): boolean => fileName === sourceFileName;
	compilerHost.getDefaultLibFileName = (): string => '';
	compilerHost.getSourceFile = (fileName: string): ts.SourceFile | undefined =>
		fileName === sourceFileName ? sourceFile : undefined;
	compilerHost.readFile = (fileName: string): string | undefined =>
		fileName === sourceFileName ? workerSource : undefined;
	const program = ts.createProgram({
		rootNames: [sourceFileName],
		options: compilerOptions,
		host: compilerHost,
	});
	const checker = program.getTypeChecker();

	return {
		checker,
		globalObjectAliasSymbols: collectGlobalObjectAliasSymbols({ checker, sourceFile }),
		sourceFile,
	};
}

interface CollectGlobalObjectAliasSymbolsProps {
	readonly checker: ts.TypeChecker;
	readonly sourceFile: ts.SourceFile;
}

function collectGlobalObjectAliasSymbols(
	props: CollectGlobalObjectAliasSymbolsProps,
): ReadonlySet<ts.Symbol> {
	const globalObjectAliasSymbols = new Set<ts.Symbol>();
	let discoveredAlias = true;

	while (discoveredAlias) {
		discoveredAlias = false;
		const visitAliasCandidate = (node: ts.Node): void => {
			let aliasIdentifier: ts.Identifier | null = null;
			let assignedExpression: ts.Expression | null = null;

			if (
				ts.isVariableDeclaration(node) &&
				ts.isIdentifier(node.name) &&
				node.initializer !== undefined
			) {
				aliasIdentifier = node.name;
				assignedExpression = node.initializer;
			} else if (
				ts.isBinaryExpression(node) &&
				node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
				ts.isIdentifier(node.left)
			) {
				aliasIdentifier = node.left;
				assignedExpression = node.right;
			}

			if (
				aliasIdentifier !== null &&
				assignedExpression !== null &&
				isGlobalObjectExpression({
					expression: assignedExpression,
					checker: props.checker,
					globalObjectAliasSymbols,
					sourceFile: props.sourceFile,
				})
			) {
				const aliasSymbol = props.checker.getSymbolAtLocation(aliasIdentifier);
				if (aliasSymbol !== undefined && !globalObjectAliasSymbols.has(aliasSymbol)) {
					globalObjectAliasSymbols.add(aliasSymbol);
					discoveredAlias = true;
				}
			}

			ts.forEachChild(node, visitAliasCandidate);
		};

		visitAliasCandidate(props.sourceFile);
	}

	return globalObjectAliasSymbols;
}

function isGlobalFetchExpression(
	expression: ts.Expression,
	workerSourceAnalysis: WorkerSourceAnalysis,
): boolean {
	const unwrappedExpression = unwrapExpression(expression);
	if (
		ts.isIdentifier(unwrappedExpression) &&
		unwrappedExpression.text === 'fetch' &&
		isIdentifierValueReference(unwrappedExpression) &&
		isAmbientGlobalIdentifier(unwrappedExpression, workerSourceAnalysis)
	) {
		return true;
	}

	if (
		ts.isPropertyAccessExpression(unwrappedExpression) &&
		unwrappedExpression.name.text === 'fetch'
	) {
		return isGlobalObjectExpression({
			expression: unwrappedExpression.expression,
			...workerSourceAnalysis,
		});
	}

	if (
		ts.isElementAccessExpression(unwrappedExpression) &&
		stringLiteralValue(unwrappedExpression.argumentExpression) === 'fetch'
	) {
		return isGlobalObjectExpression({
			expression: unwrappedExpression.expression,
			...workerSourceAnalysis,
		});
	}

	return false;
}

interface IsGlobalObjectExpressionProps {
	readonly checker: ts.TypeChecker;
	readonly expression: ts.Expression;
	readonly globalObjectAliasSymbols: ReadonlySet<ts.Symbol>;
	readonly sourceFile: ts.SourceFile;
}

function isGlobalObjectExpression(props: IsGlobalObjectExpressionProps): boolean {
	const unwrappedExpression = unwrapExpression(props.expression);
	if (!ts.isIdentifier(unwrappedExpression)) {
		return false;
	}

	const expressionSymbol = props.checker.getSymbolAtLocation(unwrappedExpression);
	if (expressionSymbol !== undefined && props.globalObjectAliasSymbols.has(expressionSymbol)) {
		return true;
	}

	return (
		['globalThis', 'self', 'window'].includes(unwrappedExpression.text) &&
		isAmbientGlobalIdentifier(unwrappedExpression, props)
	);
}

function isAmbientGlobalIdentifier(
	identifier: ts.Identifier,
	workerSourceAnalysis: Pick<WorkerSourceAnalysis, 'checker' | 'sourceFile'>,
): boolean {
	const identifierSymbol = workerSourceAnalysis.checker.getSymbolAtLocation(identifier);
	return !identifierSymbol?.declarations?.some(
		(declaration: ts.Declaration): boolean =>
			declaration.getSourceFile() === workerSourceAnalysis.sourceFile,
	);
}

function isIdentifierValueReference(identifier: ts.Identifier): boolean {
	if (ts.isPropertyAccessExpression(identifier.parent) && identifier.parent.name === identifier) {
		return false;
	}
	if (ts.isBindingElement(identifier.parent) && identifier.parent.propertyName === identifier) {
		return false;
	}
	if (ts.isShorthandPropertyAssignment(identifier.parent)) {
		return true;
	}
	const parentWithOptionalName = identifier.parent as ts.Node & { readonly name?: ts.Node };
	return parentWithOptionalName.name !== identifier;
}

function isAmbiguousLocalFetchReference(
	identifier: ts.Identifier,
	workerSourceAnalysis: WorkerSourceAnalysis,
): boolean {
	if (identifier.text !== 'fetch' || !isIdentifierValueReference(identifier)) {
		return false;
	}
	const sourceDeclarations = workerSourceAnalysis.checker
		.getSymbolAtLocation(identifier)
		?.declarations?.filter(
			(declaration: ts.Declaration): boolean =>
				declaration.getSourceFile() === workerSourceAnalysis.sourceFile,
		);
	return (
		sourceDeclarations !== undefined &&
		sourceDeclarations.length > 0 &&
		!sourceDeclarations.every(isDemonstrablyLocalFetchDeclaration)
	);
}

function isDemonstrablyLocalFetchDeclaration(declaration: ts.Declaration): boolean {
	if (ts.isFunctionDeclaration(declaration)) {
		return true;
	}
	if (!ts.isVariableDeclaration(declaration) || declaration.initializer === undefined) {
		return false;
	}
	const declarationList = declaration.parent;
	return (
		ts.isVariableDeclarationList(declarationList) &&
		(declarationList.flags & ts.NodeFlags.Const) !== 0 &&
		(ts.isArrowFunction(declaration.initializer) ||
			ts.isFunctionExpression(declaration.initializer))
	);
}

function isDirectCallCallee(expression: ts.Expression): boolean {
	return ts.isCallExpression(expression.parent) && expression.parent.expression === expression;
}

function isGlobalFetchBindingElement(
	bindingElement: ts.BindingElement,
	workerSourceAnalysis: WorkerSourceAnalysis,
): boolean {
	const bindingPropertyName = bindingElement.propertyName ?? bindingElement.name;
	if (!ts.isIdentifier(bindingPropertyName) || bindingPropertyName.text !== 'fetch') {
		return false;
	}
	if (!ts.isObjectBindingPattern(bindingElement.parent)) {
		return false;
	}

	const bindingOwner = bindingElement.parent.parent;
	return (
		ts.isVariableDeclaration(bindingOwner) &&
		bindingOwner.initializer !== undefined &&
		isGlobalObjectExpression({
			expression: bindingOwner.initializer,
			...workerSourceAnalysis,
		})
	);
}

function unwrapExpression(expression: ts.Expression): ts.Expression {
	let unwrappedExpression = expression;
	while (
		ts.isParenthesizedExpression(unwrappedExpression) ||
		ts.isAsExpression(unwrappedExpression) ||
		ts.isTypeAssertionExpression(unwrappedExpression) ||
		ts.isNonNullExpression(unwrappedExpression) ||
		ts.isPartiallyEmittedExpression(unwrappedExpression)
	) {
		unwrappedExpression = unwrappedExpression.expression;
	}
	return unwrappedExpression;
}

interface ValidateWorkerFetchCallProps {
	readonly fetchCall: ts.CallExpression;
	readonly sourceFile: ts.SourceFile;
	readonly workerAssetKind: string;
}

function validateWorkerFetchCall(props: ValidateWorkerFetchCallProps): void {
	if (props.workerAssetKind !== bridgeCommWorkerAssetKind) {
		throwWorkerSelfContainmentError(props.sourceFile, props.fetchCall, 'fetch(...)');
	}

	const route = stringLiteralValue(props.fetchCall.arguments[0]);
	if (route === null || !bridgeProductRoutes.has(route)) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			'non-product or dynamic fetch route',
		);
	}

	const requestInit = props.fetchCall.arguments[1];
	if (requestInit === undefined || !ts.isObjectLiteralExpression(requestInit)) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			'product fetch without literal request init',
		);
	}

	const methodProperty = requiredUniqueObjectProperty({
		objectLiteral: requestInit,
		propertyName: 'method',
		sourceFile: props.sourceFile,
		fetchCall: props.fetchCall,
	});
	if (stringLiteralValue(methodProperty.initializer) !== bridgeProductRequestMethod) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			'product fetch without literal POST method',
		);
	}

	const headersProperty = requiredUniqueObjectProperty({
		objectLiteral: requestInit,
		propertyName: 'headers',
		sourceFile: props.sourceFile,
		fetchCall: props.fetchCall,
	});
	if (!ts.isObjectLiteralExpression(headersProperty.initializer)) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			'product fetch without literal capability headers',
		);
	}
	const contentTypeProperty = requiredUniqueObjectProperty({
		objectLiteral: headersProperty.initializer,
		propertyName: bridgeProductContentTypeHeaderName,
		sourceFile: props.sourceFile,
		fetchCall: props.fetchCall,
	});
	if (stringLiteralValue(contentTypeProperty.initializer) !== bridgeProductContentType) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			'product fetch without literal application/json content type',
		);
	}
	requiredUniqueObjectProperty({
		objectLiteral: headersProperty.initializer,
		propertyName: bridgeProductCapabilityHeaderName,
		sourceFile: props.sourceFile,
		fetchCall: props.fetchCall,
	});
	if (headersProperty.initializer.properties.length !== 2) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			'product fetch with headers beyond content type and capability',
		);
	}
}

interface RequiredUniqueObjectPropertyProps {
	readonly objectLiteral: ts.ObjectLiteralExpression;
	readonly propertyName: string;
	readonly sourceFile: ts.SourceFile;
	readonly fetchCall: ts.CallExpression;
}

function requiredUniqueObjectProperty(
	props: RequiredUniqueObjectPropertyProps,
): ts.PropertyAssignment {
	const propertyAssignments: ts.PropertyAssignment[] = [];
	for (const property of props.objectLiteral.properties) {
		if (!ts.isPropertyAssignment(property)) {
			throwWorkerSelfContainmentError(
				props.sourceFile,
				props.fetchCall,
				'product fetch with dynamic request properties',
			);
		}
		const propertyName = propertyNameValue(property.name);
		if (propertyName === null) {
			throwWorkerSelfContainmentError(
				props.sourceFile,
				props.fetchCall,
				'product fetch with computed request properties',
			);
		}
		if (propertyName === props.propertyName) {
			propertyAssignments.push(property);
		}
	}

	const propertyAssignment = propertyAssignments[0];
	if (propertyAssignments.length !== 1 || propertyAssignment === undefined) {
		throwWorkerSelfContainmentError(
			props.sourceFile,
			props.fetchCall,
			`product fetch without one literal ${props.propertyName} property`,
		);
	}
	return propertyAssignment;
}

function propertyNameValue(propertyName: ts.PropertyName): string | null {
	if (
		ts.isIdentifier(propertyName) ||
		ts.isStringLiteral(propertyName) ||
		ts.isNumericLiteral(propertyName)
	) {
		return propertyName.text;
	}
	return null;
}

function stringLiteralValue(node: ts.Node | undefined): string | null {
	if (node === undefined) {
		return null;
	}
	if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
		return node.text;
	}
	return null;
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

function sumAssetBytes(assets: readonly AppAssetRecord[]): number {
	return assets.reduce(
		(totalBytes: number, asset: AppAssetRecord): number => totalBytes + asset.bytes,
		0,
	);
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
