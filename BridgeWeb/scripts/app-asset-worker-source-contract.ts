import ts from 'typescript';

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

export interface WorkerSourceSelfContainmentCheck {
	readonly isSelfContained: true;
	readonly checkedPatterns: readonly string[];
}

export interface ValidateWorkerSourceSelfContainedProps {
	readonly workerAssetKind: string;
	readonly workerSource: string;
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
				workerSourceAnalysis,
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
	readonly workerSourceAnalysis: WorkerSourceAnalysis;
	readonly workerAssetKind: string;
}

function validateWorkerFetchCall(props: ValidateWorkerFetchCallProps): void {
	const { sourceFile } = props.workerSourceAnalysis;
	if (props.workerAssetKind !== bridgeCommWorkerAssetKind) {
		throwWorkerSelfContainmentError(sourceFile, props.fetchCall, 'fetch(...)');
	}

	const route = exactProductRouteValue(props.fetchCall.arguments[0], props.workerSourceAnalysis);
	if (route === null || !bridgeProductRoutes.has(route)) {
		throwWorkerSelfContainmentError(
			sourceFile,
			props.fetchCall,
			'non-product or dynamic fetch route',
		);
	}

	const requestInit = props.fetchCall.arguments[1];
	if (requestInit === undefined || !ts.isObjectLiteralExpression(requestInit)) {
		throwWorkerSelfContainmentError(
			sourceFile,
			props.fetchCall,
			'product fetch without literal request init',
		);
	}

	const methodProperty = requiredUniqueObjectProperty({
		objectLiteral: requestInit,
		propertyName: 'method',
		sourceFile,
		fetchCall: props.fetchCall,
	});
	if (stringLiteralValue(methodProperty.initializer) !== bridgeProductRequestMethod) {
		throwWorkerSelfContainmentError(
			sourceFile,
			props.fetchCall,
			'product fetch without literal POST method',
		);
	}

	const headersProperty = requiredUniqueObjectProperty({
		objectLiteral: requestInit,
		propertyName: 'headers',
		sourceFile,
		fetchCall: props.fetchCall,
	});
	if (!ts.isObjectLiteralExpression(headersProperty.initializer)) {
		throwWorkerSelfContainmentError(
			sourceFile,
			props.fetchCall,
			'product fetch without literal capability headers',
		);
	}
	const contentTypeProperty = requiredUniqueObjectProperty({
		objectLiteral: headersProperty.initializer,
		propertyName: bridgeProductContentTypeHeaderName,
		sourceFile,
		fetchCall: props.fetchCall,
	});
	if (stringLiteralValue(contentTypeProperty.initializer) !== bridgeProductContentType) {
		throwWorkerSelfContainmentError(
			sourceFile,
			props.fetchCall,
			'product fetch without literal application/json content type',
		);
	}
	requiredUniqueObjectProperty({
		objectLiteral: headersProperty.initializer,
		propertyName: bridgeProductCapabilityHeaderName,
		sourceFile,
		fetchCall: props.fetchCall,
	});
	if (headersProperty.initializer.properties.length !== 2) {
		throwWorkerSelfContainmentError(
			sourceFile,
			props.fetchCall,
			'product fetch with headers beyond content type and capability',
		);
	}
}

function exactProductRouteValue(
	expression: ts.Expression | undefined,
	workerSourceAnalysis: WorkerSourceAnalysis,
): string | null {
	const inlineRoute = stringLiteralValue(expression);
	if (inlineRoute !== null) return inlineRoute;
	if (expression === undefined) return null;

	const unwrappedExpression = unwrapExpression(expression);
	if (!ts.isIdentifier(unwrappedExpression)) return null;
	const declarations =
		workerSourceAnalysis.checker.getSymbolAtLocation(unwrappedExpression)?.declarations;
	if (declarations?.length !== 1) return null;
	const declaration = declarations[0];
	if (
		declaration === undefined ||
		!ts.isVariableDeclaration(declaration) ||
		declaration.initializer === undefined ||
		declaration.getSourceFile() !== workerSourceAnalysis.sourceFile
	) {
		return null;
	}
	const declarationList = declaration.parent;
	if (
		!ts.isVariableDeclarationList(declarationList) ||
		(declarationList.flags & ts.NodeFlags.Const) === 0 ||
		!ts.isVariableStatement(declarationList.parent) ||
		declarationList.parent.parent !== workerSourceAnalysis.sourceFile
	) {
		return null;
	}
	return stringLiteralValue(declaration.initializer);
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
