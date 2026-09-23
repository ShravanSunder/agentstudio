import { join, matchesGlob, relative } from 'node:path';

import ts from 'typescript';

// Rule `no-timed-wait-in-tests`: a BridgeWeb test wait completes because an
// application event or a DOM condition occurred, never because time passed.
//
// Roots are the real test inventory: every file matched by an `include` glob or
// named in `setupFiles` of any `vitest*.config.ts`. The rule follows each root's
// runtime imports (resolved by TypeScript with BridgeWeb's tsconfig) into test
// harness modules only (see `isTestHarnessModulePath`) and stops at production
// modules: a product deadline is product behavior, not a test wait. It reports,
// in every root and reachable harness module:
// - `waitForTimeout(...)`;
// - an awaited sleep/delay helper, or an awaited `setTimeout` from
//   `node:timers/promises`;
// - an awaited `new Promise` whose only resolution is a timer, whatever its delay
//   (a zero-delay timer is still a wait on time);
// - any other timer that settles a promise (a deadline or race), unless its delay
//   is one of the shared hang bounds exported by `tests/vitest-hang-bounds.ts`.

export interface TimedWaitSourceFile {
	readonly relativePath: string;
	readonly sourceFile: ts.SourceFile;
}

export interface FindTimedWaitsInTestImportClosureProps {
	readonly packageRootPath: string;
	readonly sourceFiles: readonly TimedWaitSourceFile[];
}

export interface TimedWaitFinding {
	readonly column: number;
	readonly line: number;
	readonly message: string;
	readonly relativePath: string;
}

const vitestConfigPathPattern = /^vitest(?:\.[\w-]+)?\.config\.ts$/u;
const testFilePathPattern =
	/\.test\.[cm]?[jt]sx?$|\.browser\.[a-z0-9-]+-suite\.[cm]?[jt]sx?$|\.benchmark\.[cm]?[jt]sx?$/u;
const testHelperPathPattern = /(?:^|[/.-])test-(?:actions|fixtures?|helpers?|support)(?:[/.-]|$)/u;
// Directories that hold only test harness code: E2E journeys and fixtures, the
// dev-server verifier, and the owned development-server process harness.
const testHarnessDirectoryPrefixes: readonly string[] = [
	'tests/',
	'scripts/verify-',
	'scripts/dev-server/',
];
const hangBoundModulePath = 'tests/vitest-hang-bounds.ts';
const sleepHelperNamePattern = /^(?:sleep|delay)(?:[A-Z0-9_]\w*)?$/u;
const timerFunctionNames = new Set(['setTimeout', 'setInterval']);
const defaultCompilerOptions: ts.CompilerOptions = {
	allowImportingTsExtensions: true,
	module: ts.ModuleKind.NodeNext,
	moduleResolution: ts.ModuleResolutionKind.NodeNext,
	noEmit: true,
};

interface ModuleResolutionContext {
	readonly compilerOptions: ts.CompilerOptions;
	readonly packageRootPath: string;
	readonly sourceFilesByPath: ReadonlyMap<string, TimedWaitSourceFile>;
}

export function findTimedWaitsInTestImportClosure(
	props: FindTimedWaitsInTestImportClosureProps,
): readonly TimedWaitFinding[] {
	const resolution: ModuleResolutionContext = {
		compilerOptions: readPackageCompilerOptions(props.packageRootPath),
		packageRootPath: props.packageRootPath,
		sourceFilesByPath: new Map(
			props.sourceFiles.map((sourceFile: TimedWaitSourceFile): [string, TimedWaitSourceFile] => [
				sourceFile.relativePath,
				sourceFile,
			]),
		),
	};
	const reachingTestRootByPath = collectTestImportClosure(resolution);
	const findings: TimedWaitFinding[] = [];

	for (const [relativePath, reachingTestRoot] of reachingTestRootByPath) {
		const closureFile = resolution.sourceFilesByPath.get(relativePath);
		if (closureFile === undefined) continue;
		const reachability =
			reachingTestRoot === relativePath
				? 'test file'
				: `module imported by test file ${reachingTestRoot}`;
		const hangBoundNames = importedHangBoundNames(closureFile, resolution);
		visitNodes(closureFile.sourceFile, (node: ts.Node): void => {
			const timedWaitDescription = describeTimedWait(node, hangBoundNames);
			if (timedWaitDescription === null) return;
			const position = closureFile.sourceFile.getLineAndCharacterOfPosition(
				node.getStart(closureFile.sourceFile),
			);
			findings.push({
				column: position.character + 1,
				line: position.line + 1,
				relativePath,
				message: `${timedWaitDescription} in a ${reachability}; a test wait must complete on an application event or DOM condition, and a timer may only bound it with a hang bound from ${hangBoundModulePath}`,
			});
		});
	}

	return findings;
}

function readPackageCompilerOptions(packageRootPath: string): ts.CompilerOptions {
	const tsconfigPath = join(packageRootPath, 'tsconfig.json');
	if (!ts.sys.fileExists(tsconfigPath)) return defaultCompilerOptions;
	const configFile = ts.readConfigFile(tsconfigPath, (path: string): string | undefined =>
		ts.sys.readFile(path),
	);
	if (configFile.error !== undefined) {
		throw new Error(
			`Cannot read ${tsconfigPath}: ${ts.flattenDiagnosticMessageText(configFile.error.messageText, '\n')}`,
		);
	}
	return ts.parseJsonConfigFileContent(
		configFile.config,
		ts.sys,
		packageRootPath,
		undefined,
		tsconfigPath,
	).options;
}

// Breadth-first from every test root, remembering the first root that reaches
// each module so a finding can name how a test depends on it.
function collectTestImportClosure(
	resolution: ModuleResolutionContext,
): ReadonlyMap<string, string> {
	const reachingTestRootByPath = new Map<string, string>();
	const pendingPaths: string[] = [];
	for (const relativePath of collectTestRootPaths(resolution.sourceFilesByPath)) {
		reachingTestRootByPath.set(relativePath, relativePath);
		pendingPaths.push(relativePath);
	}

	for (let pendingIndex = 0; pendingIndex < pendingPaths.length; pendingIndex += 1) {
		const importerPath = pendingPaths[pendingIndex];
		if (importerPath === undefined) continue;
		const importerFile = resolution.sourceFilesByPath.get(importerPath);
		const reachingTestRoot = reachingTestRootByPath.get(importerPath);
		if (importerFile === undefined || reachingTestRoot === undefined) continue;
		for (const importSpecifier of readRuntimeImportSpecifiers(importerFile.sourceFile)) {
			const importedPath = resolveImportedSourcePath(importerFile, importSpecifier, resolution);
			if (importedPath === null || reachingTestRootByPath.has(importedPath)) continue;
			if (!isTestHarnessModulePath(importedPath)) continue;
			reachingTestRootByPath.set(importedPath, reachingTestRoot);
			pendingPaths.push(importedPath);
		}
	}

	return reachingTestRootByPath;
}

export function isTestHarnessModulePath(relativePath: string): boolean {
	return (
		testFilePathPattern.test(relativePath) ||
		testHelperPathPattern.test(relativePath) ||
		testHarnessDirectoryPrefixes.some((prefix: string): boolean => relativePath.startsWith(prefix))
	);
}

function collectTestRootPaths(
	sourceFilesByPath: ReadonlyMap<string, TimedWaitSourceFile>,
): readonly string[] {
	const includeGlobs: string[] = [];
	const setupFilePaths: string[] = [];
	for (const [relativePath, configFile] of sourceFilesByPath) {
		if (!vitestConfigPathPattern.test(relativePath)) continue;
		visitNodes(configFile.sourceFile, (node: ts.Node): void => {
			if (!ts.isPropertyAssignment(node) || !ts.isArrayLiteralExpression(node.initializer)) return;
			const propertyName = ts.isIdentifier(node.name) ? node.name.text : null;
			const values = node.initializer.elements.flatMap((element: ts.Expression): string[] =>
				ts.isStringLiteralLike(element) ? [element.text] : [],
			);
			if (propertyName === 'include') includeGlobs.push(...values);
			if (propertyName === 'setupFiles') {
				setupFilePaths.push(...values.map((value: string): string => value.replace(/^\.\//u, '')));
			}
		});
	}
	return [...sourceFilesByPath.keys()]
		.filter(
			(relativePath: string): boolean =>
				setupFilePaths.includes(relativePath) ||
				includeGlobs.some((includeGlob: string): boolean => matchesGlob(relativePath, includeGlob)),
		)
		.toSorted();
}

function readRuntimeImportSpecifiers(sourceFile: ts.SourceFile): readonly string[] {
	const importSpecifiers: string[] = [];
	visitNodes(sourceFile, (node: ts.Node): void => {
		if (ts.isImportDeclaration(node)) {
			if (node.importClause?.isTypeOnly === true) return;
			if (ts.isStringLiteral(node.moduleSpecifier))
				importSpecifiers.push(node.moduleSpecifier.text);
			return;
		}
		if (ts.isExportDeclaration(node)) {
			if (node.isTypeOnly || node.moduleSpecifier === undefined) return;
			if (ts.isStringLiteral(node.moduleSpecifier))
				importSpecifiers.push(node.moduleSpecifier.text);
			return;
		}
		if (
			ts.isCallExpression(node) &&
			node.expression.kind === ts.SyntaxKind.ImportKeyword &&
			node.arguments.length === 1
		) {
			const importArgument = node.arguments[0];
			if (importArgument !== undefined && ts.isStringLiteralLike(importArgument)) {
				importSpecifiers.push(importArgument.text);
			}
		}
	});
	return importSpecifiers;
}

function resolveImportedSourcePath(
	importerFile: TimedWaitSourceFile,
	importSpecifier: string,
	resolution: ModuleResolutionContext,
): string | null {
	const resolvedModule = ts.resolveModuleName(
		importSpecifier.replace(/[?#].*$/u, ''),
		importerFile.sourceFile.fileName,
		resolution.compilerOptions,
		ts.sys,
	).resolvedModule;
	if (resolvedModule === undefined || resolvedModule.isExternalLibraryImport === true) return null;
	const relativePath = relative(
		resolution.packageRootPath,
		resolvedModule.resolvedFileName,
	).replaceAll('\\', '/');
	return resolution.sourceFilesByPath.has(relativePath) ? relativePath : null;
}

// Local names bound to the shared hang-bound constants in this module.
function importedHangBoundNames(
	closureFile: TimedWaitSourceFile,
	resolution: ModuleResolutionContext,
): ReadonlySet<string> {
	const names = new Set<string>();
	for (const statement of closureFile.sourceFile.statements) {
		if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier))
			continue;
		const namedBindings = statement.importClause?.namedBindings;
		if (namedBindings === undefined || !ts.isNamedImports(namedBindings)) continue;
		if (
			resolveImportedSourcePath(closureFile, statement.moduleSpecifier.text, resolution) !==
			hangBoundModulePath
		) {
			continue;
		}
		for (const element of namedBindings.elements) names.add(element.name.text);
	}
	return names;
}

function describeTimedWait(node: ts.Node, hangBoundNames: ReadonlySet<string>): string | null {
	if (ts.isCallExpression(node) && calleeName(node.expression) === 'waitForTimeout') {
		return 'waitForTimeout()';
	}
	if (ts.isAwaitExpression(node)) {
		const awaitedExpression = skipParentheses(node.expression);
		if (ts.isCallExpression(awaitedExpression)) {
			const awaitedCalleeName = calleeName(awaitedExpression.expression);
			if (awaitedCalleeName !== null && sleepHelperNamePattern.test(awaitedCalleeName)) {
				return `awaited ${awaitedCalleeName}()`;
			}
			if (awaitedCalleeName === 'setTimeout') return 'awaited timers/promises setTimeout()';
		}
		return null;
	}
	if (!ts.isNewExpression(node)) return null;
	const timerSettlement = describeTimerSettledPromise(node);
	if (timerSettlement === null) return null;
	if (timerSettlement.timerOnlyResolution && isAwaited(node)) {
		return 'awaited Promise resolved only by a timer';
	}
	if (timerSettlement.delays.every((delay): boolean => referencesAny(delay, hangBoundNames))) {
		return null;
	}
	return 'timer deadline whose delay is not a shared hang bound';
}

interface TimerSettledPromise {
	readonly delays: readonly ts.Expression[];
	readonly timerOnlyResolution: boolean;
}

// A `new Promise` whose executor settles it (resolve or reject) from a timer.
function describeTimerSettledPromise(expression: ts.NewExpression): TimerSettledPromise | null {
	if (!ts.isIdentifier(expression.expression) || expression.expression.text !== 'Promise') {
		return null;
	}
	const executor = expression.arguments?.[0];
	if (
		executor === undefined ||
		(!ts.isArrowFunction(executor) && !ts.isFunctionExpression(executor))
	) {
		return null;
	}
	const settleNames = new Set(
		executor.parameters.flatMap((parameter): string[] =>
			ts.isIdentifier(parameter.name) ? [parameter.name.text] : [],
		),
	);
	const resolveName = executor.parameters[0]?.name;
	const delays: ts.Expression[] = [];
	let resolveReferenceCount = 0;
	let timerResolveReferenceCount = 0;
	visitNodes(executor.body, (node: ts.Node): void => {
		if (!ts.isIdentifier(node) || !settleNames.has(node.text)) return;
		const timerCall = enclosingTimerCall(node, executor);
		const isResolve =
			resolveName !== undefined && ts.isIdentifier(resolveName) && node.text === resolveName.text;
		if (isResolve) resolveReferenceCount += 1;
		if (timerCall === null) return;
		if (isResolve) timerResolveReferenceCount += 1;
		delays.push(timerCall.arguments[1] ?? ts.factory.createNumericLiteral(0));
	});
	if (delays.length === 0) return null;
	return {
		delays,
		timerOnlyResolution:
			resolveReferenceCount > 0 && resolveReferenceCount === timerResolveReferenceCount,
	};
}

function enclosingTimerCall(node: ts.Node, boundary: ts.Node): ts.CallExpression | null {
	let child: ts.Node = node;
	let ancestor: ts.Node | undefined = node.parent;
	while (ancestor !== undefined && child !== boundary) {
		if (
			ts.isCallExpression(ancestor) &&
			ancestor.arguments.some((argument: ts.Expression): boolean => argument === child) &&
			timerFunctionNames.has(calleeName(ancestor.expression) ?? '')
		) {
			return ancestor;
		}
		child = ancestor;
		ancestor = ancestor.parent;
	}
	return null;
}

function isAwaited(expression: ts.Expression): boolean {
	let parent = expression.parent;
	while (ts.isParenthesizedExpression(parent)) parent = parent.parent;
	return ts.isAwaitExpression(parent);
}

function referencesAny(expression: ts.Node, names: ReadonlySet<string>): boolean {
	if (ts.isIdentifier(expression)) return names.has(expression.text);
	let found = false;
	expression.forEachChild((child: ts.Node): void => {
		if (!found && referencesAny(child, names)) found = true;
	});
	return found;
}

function calleeName(expression: ts.Expression): string | null {
	if (ts.isIdentifier(expression)) return expression.text;
	if (ts.isPropertyAccessExpression(expression)) return expression.name.text;
	return null;
}

function skipParentheses(expression: ts.Expression): ts.Expression {
	return ts.isParenthesizedExpression(expression)
		? skipParentheses(expression.expression)
		: expression;
}

function visitNodes(node: ts.Node, visitNode: (node: ts.Node) => void): void {
	visitNode(node);
	node.forEachChild((childNode: ts.Node): void => visitNodes(childNode, visitNode));
}
