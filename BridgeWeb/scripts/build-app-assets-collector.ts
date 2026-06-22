import type { Dirent } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { basename, extname, join, relative } from 'node:path';

import ts from 'typescript';

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
	const sourceFile = ts.createSourceFile(
		scriptPath,
		script,
		ts.ScriptTarget.ES2022,
		true,
		ts.ScriptKind.JS,
	);

	visitScriptModuleSpecifiers({ sourceFile, scriptPath });

	const externalUrlSource = String.raw`(?:https?:|//|data:|blob:|file:|agentstudio://(?!app/))`;
	const externalRuntimePatterns: readonly RegExp[] = [
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

interface VisitScriptModuleSpecifiersProps {
	readonly sourceFile: ts.SourceFile;
	readonly scriptPath: string;
}

function visitScriptModuleSpecifiers(props: VisitScriptModuleSpecifiersProps): void {
	const visit = (node: ts.Node): void => {
		const moduleSpecifier = moduleSpecifierFromNode(node);
		if (moduleSpecifier !== null) {
			validatePackagedScriptModuleSpecifier({
				moduleSpecifier,
				scriptPath: props.scriptPath,
			});
		}

		if (isNonLiteralDynamicImport(node)) {
			throw new Error(
				`Packaged app script contains non-literal dynamic import: ${props.scriptPath}`,
			);
		}

		if (ts.isNewExpression(node) && isWorkerConstructorExpression(node.expression)) {
			validatePackagedWorkerConstructor({
				sourceFile: props.sourceFile,
				node,
				scriptPath: props.scriptPath,
			});
		}

		ts.forEachChild(node, visit);
	};

	visit(props.sourceFile);
}

function moduleSpecifierFromNode(node: ts.Node): string | null {
	if (
		(ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) &&
		node.moduleSpecifier !== undefined &&
		ts.isStringLiteralLike(node.moduleSpecifier)
	) {
		return node.moduleSpecifier.text;
	}

	if (
		ts.isCallExpression(node) &&
		node.expression.kind === ts.SyntaxKind.ImportKeyword &&
		node.arguments.length === 1
	) {
		const argument = node.arguments[0];
		if (argument !== undefined && ts.isStringLiteralLike(argument)) {
			return argument.text;
		}
	}

	return null;
}

function isNonLiteralDynamicImport(node: ts.Node): boolean {
	if (
		!ts.isCallExpression(node) ||
		node.expression.kind !== ts.SyntaxKind.ImportKeyword ||
		node.arguments.length !== 1
	) {
		return false;
	}

	const argument = node.arguments[0];
	return argument === undefined || !ts.isStringLiteralLike(argument);
}

function isWorkerConstructorExpression(expression: ts.Expression): boolean {
	return (
		isIdentifierExpression(expression, 'Worker') ||
		isIdentifierExpression(expression, 'SharedWorker')
	);
}

interface ValidatePackagedWorkerConstructorProps {
	readonly sourceFile: ts.SourceFile;
	readonly node: ts.NewExpression;
	readonly scriptPath: string;
}

function validatePackagedWorkerConstructor(props: ValidatePackagedWorkerConstructorProps): void {
	const workerUrlExpression = props.node.arguments?.[0];
	if (workerUrlExpression === undefined) {
		throw new Error(`Packaged app script contains non-literal worker URL: ${props.scriptPath}`);
	}

	const workerUrl = workerUrlFromExpression({
		sourceFile: props.sourceFile,
		expression: workerUrlExpression,
	});
	if (workerUrl !== null && isExternalRuntimeSpecifier(workerUrl)) {
		throw new Error(`Packaged app script contains external runtime import: ${props.scriptPath}`);
	}
}

interface WorkerUrlFromExpressionProps {
	readonly sourceFile: ts.SourceFile;
	readonly expression: ts.Expression;
}

function workerUrlFromExpression(props: WorkerUrlFromExpressionProps): string | null {
	if (ts.isStringLiteralLike(props.expression)) {
		return props.expression.text;
	}

	if (
		ts.isNewExpression(props.expression) &&
		isIdentifierExpression(props.expression.expression, 'URL')
	) {
		const urlArgument = props.expression.arguments?.[0];
		return urlArgument !== undefined && ts.isStringLiteralLike(urlArgument)
			? urlArgument.text
			: null;
	}

	if (ts.isIdentifier(props.expression)) {
		return resolveStringInitializer({
			sourceFile: props.sourceFile,
			identifierText: props.expression.text,
		});
	}

	return null;
}

interface ResolveStringInitializerProps {
	readonly sourceFile: ts.SourceFile;
	readonly identifierText: string;
}

function resolveStringInitializer(props: ResolveStringInitializerProps): string | null {
	let resolvedInitializer: string | null = null;
	const visit = (node: ts.Node): void => {
		if (resolvedInitializer !== null || !ts.isVariableDeclaration(node)) {
			ts.forEachChild(node, visit);
			return;
		}

		if (
			ts.isIdentifier(node.name) &&
			node.name.text === props.identifierText &&
			node.initializer !== undefined
		) {
			resolvedInitializer = initializerStringValue(node.initializer);
		}

		ts.forEachChild(node, visit);
	};

	visit(props.sourceFile);
	return resolvedInitializer;
}

function initializerStringValue(initializer: ts.Expression): string | null {
	if (ts.isStringLiteralLike(initializer)) {
		return initializer.text;
	}

	if (ts.isNewExpression(initializer) && isIdentifierExpression(initializer.expression, 'URL')) {
		const urlArgument = initializer.arguments?.[0];
		return urlArgument !== undefined && ts.isStringLiteralLike(urlArgument)
			? urlArgument.text
			: null;
	}

	return null;
}

interface ValidatePackagedScriptModuleSpecifierProps {
	readonly moduleSpecifier: string;
	readonly scriptPath: string;
}

function validatePackagedScriptModuleSpecifier(
	props: ValidatePackagedScriptModuleSpecifierProps,
): void {
	if (isExternalRuntimeSpecifier(props.moduleSpecifier)) {
		throw new Error(`Packaged app script contains external runtime import: ${props.scriptPath}`);
	}

	if (!isPackagedRelativeModuleSpecifier(props.moduleSpecifier)) {
		throw new Error(`Packaged app script still imports runtime packages: ${props.scriptPath}`);
	}
}

function isPackagedRelativeModuleSpecifier(moduleSpecifier: string): boolean {
	return moduleSpecifier.startsWith('./') || moduleSpecifier.startsWith('../');
}

function isExternalRuntimeSpecifier(moduleSpecifier: string): boolean {
	return /^(?:https?:|\/\/|data:|blob:|file:|agentstudio:\/\/(?!app\/))/u.test(moduleSpecifier);
}

function isIdentifierExpression(expression: ts.Expression, identifierText: string): boolean {
	return ts.isIdentifier(expression) && expression.text === identifierText;
}
