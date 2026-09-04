import { dirname, extname, join, normalize } from 'node:path';

import ts from 'typescript';

import {
	explicitStyledElementKind,
	isKnownLayoutUtility,
	isProhibitedInlineStyleProperty,
	isProhibitedUtility,
	isRawPaletteUtility,
	type StyledElementKind,
} from './check-bridgeweb-style-system-classification.ts';
import {
	findingAtNode,
	findingAtPosition,
	type StyleSystemFinding,
} from './check-bridgeweb-style-system-model.ts';
import {
	classifyJsxRole,
	resolveJsxStylingSpreads,
} from './check-bridgeweb-style-system-typescript-jsx-resolution.ts';
import {
	checkInlineStyleExpressionColors,
	checkJsxPolicy,
	checkTypeScriptPolicyNode,
} from './check-bridgeweb-style-system-typescript-policy.ts';
import {
	resolveStaticClasses,
	unwrapExpression,
} from './check-bridgeweb-style-system-typescript-resolution.ts';

export interface TypeScriptSourceRecord {
	readonly relativePath: string;
	readonly sourceText: string;
	readonly sourceFile: ts.SourceFile;
}

interface ImportBinding {
	readonly importedName: string;
	readonly targetPath: string | null;
	readonly moduleSpecifier: string;
}

export function createTypeScriptSourceRecord(props: {
	readonly sourceText: string;
	readonly relativePath: string;
}): TypeScriptSourceRecord {
	return {
		...props,
		sourceFile: ts.createSourceFile(
			props.relativePath,
			props.sourceText,
			ts.ScriptTarget.Latest,
			true,
			props.relativePath.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
		),
	};
}

export function typeScriptParseFindings(
	record: TypeScriptSourceRecord,
): readonly StyleSystemFinding[] {
	const parseDiagnostics: unknown = Reflect.get(record.sourceFile, 'parseDiagnostics');
	if (!Array.isArray(parseDiagnostics)) {
		return [
			findingAtPosition({
				ruleId: 'evaluation-failure',
				relativePath: record.relativePath,
				sourceFile: record.sourceFile,
				position: 0,
				message: 'TypeScript parser did not expose syntax diagnostics.',
			}),
		];
	}
	return parseDiagnostics.filter(isDiagnosticWithLocation).map((diagnostic) =>
		findingAtPosition({
			ruleId: 'evaluation-failure',
			relativePath: record.relativePath,
			sourceFile: diagnostic.file,
			position: diagnostic.start,
			message: `TypeScript parse failed: ${ts.flattenDiagnosticMessageText(diagnostic.messageText, ' ')}`,
		}),
	);
}

function isDiagnosticWithLocation(value: unknown): value is ts.DiagnosticWithLocation {
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	const diagnosticStart = Reflect.get(value, 'start');
	const diagnosticFile = Reflect.get(value, 'file');
	const diagnosticMessage = Reflect.get(value, 'messageText');
	return (
		typeof diagnosticStart === 'number' &&
		typeof diagnosticFile === 'object' &&
		diagnosticFile !== null &&
		(typeof diagnosticMessage === 'string' || typeof diagnosticMessage === 'object')
	);
}

export function analyzeTypeScriptSources(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	customClassStyleProperties: ReadonlyMap<string, ReadonlySet<string>>,
): readonly StyleSystemFinding[] {
	const findings: StyleSystemFinding[] = [];
	for (const record of records.values()) {
		if (isTestPath(record.relativePath)) {
			continue;
		}
		walk(record.sourceFile, (node: ts.Node): void => {
			checkTypeScriptPolicyNode(records, record, node, findings);
			if (ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) {
				checkJsxPolicy({ records, record, element: node, findings });
				checkStyledElementOverrides(records, customClassStyleProperties, record, node, findings);
			}
		});
	}
	return findings;
}

export function readPaletteMirror(record: TypeScriptSourceRecord): {
	readonly entries: ReadonlyMap<string, string>;
	readonly duplicateNames: readonly string[];
} {
	const entries = new Map<string, string>();
	const duplicateNames: string[] = [];
	let paletteObject: ts.ObjectLiteralExpression | undefined;
	for (const statement of record.sourceFile.statements) {
		if (!ts.isVariableStatement(statement)) {
			continue;
		}
		for (const declaration of statement.declarationList.declarations) {
			if (!ts.isIdentifier(declaration.name) || declaration.name.text !== 'bridgeDesignPalette') {
				continue;
			}
			const initializer = unwrapExpression(declaration.initializer);
			if (initializer !== null && ts.isObjectLiteralExpression(initializer)) {
				paletteObject = initializer;
			}
		}
	}
	if (paletteObject === undefined) {
		throw new Error('bridgeDesignPalette must be a static object literal');
	}
	for (const property of paletteObject.properties) {
		if (!ts.isPropertyAssignment(property)) {
			throw new Error('bridgeDesignPalette may contain only property assignments');
		}
		const name = propertyNameText(property.name);
		const value = unwrapExpression(property.initializer);
		if (name === null || value === null || !ts.isStringLiteralLike(value)) {
			throw new Error('bridgeDesignPalette keys and values must be string literals');
		}
		if (entries.has(name)) {
			duplicateNames.push(name);
		}
		entries.set(name, normalizePaletteValue(value.text));
	}
	return { entries, duplicateNames };
}

function checkStyledElementOverrides(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	customClassStyleProperties: ReadonlyMap<string, ReadonlySet<string>>,
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	findings: StyleSystemFinding[],
): void {
	if (record.relativePath.startsWith('src/components/ui/')) {
		return;
	}
	const tagName = element.tagName.getText();
	const elementKind = styledElementKind(records, record, element, new Set());
	if (elementKind === null) {
		return;
	}
	checkInlineStyle(record, element, elementKind, findings);
	const spreadResolution = isDirectStyledElement(records, record, element)
		? resolveJsxStylingSpreads(record, element)
		: { classExpressions: [], styleExpressions: [], unknownStyling: false };
	for (const classExpression of spreadResolution.classExpressions) {
		checkClassExpression(
			records,
			customClassStyleProperties,
			record,
			classExpression,
			classExpression,
			elementKind,
			tagName,
			findings,
		);
	}
	for (const styleExpression of spreadResolution.styleExpressions) {
		checkInlineStyleExpressionColors(record, styleExpression, styleExpression, findings);
		checkInlineStyleExpression(record, styleExpression, styleExpression, elementKind, findings);
	}
	if (spreadResolution.unknownStyling) {
		findings.push(
			findingAtNode({
				ruleId: 'unknown-control-classes',
				relativePath: record.relativePath,
				node: element,
				message: `Cannot statically classify JSX spread styling for ${styledElementLabel(elementKind).toLowerCase()} <${tagName}>.`,
			}),
		);
	}
	const classAttribute = element.attributes.properties.find(
		(attribute): attribute is ts.JsxAttribute =>
			ts.isJsxAttribute(attribute) && attribute.name.getText() === 'className',
	);
	if (classAttribute?.initializer === undefined) {
		return;
	}
	const classExpression = jsxAttributeExpression(classAttribute.initializer);
	if (classExpression === null) {
		return;
	}
	checkClassExpression(
		records,
		customClassStyleProperties,
		record,
		classExpression,
		classAttribute,
		elementKind,
		tagName,
		findings,
	);
}

function isDirectStyledElement(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
): boolean {
	const tagName = element.tagName.getText();
	if (['button', 'input', 'select', 'textarea'].includes(tagName)) return true;
	if (classifyJsxRole(element) === 'control') return true;
	const binding = importsForRecord(record, records).get(tagName);
	return (
		binding !== undefined &&
		(binding.moduleSpecifier.includes('/components/ui/') ||
			binding.moduleSpecifier.startsWith('@/components/ui/')) &&
		explicitStyledElementKind(binding.importedName) !== null
	);
}

function checkClassExpression(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	customClassStyleProperties: ReadonlyMap<string, ReadonlySet<string>>,
	record: TypeScriptSourceRecord,
	classExpression: ts.Expression,
	findingNode: ts.Node,
	elementKind: StyledElementKind,
	tagName: string,
	findings: StyleSystemFinding[],
): void {
	const classResult = resolveStaticClasses(records, record, classExpression, new Set());
	if (classResult.unknown) {
		findings.push(
			findingAtNode({
				ruleId: 'unknown-control-classes',
				relativePath: record.relativePath,
				node: findingNode,
				message: `Cannot statically classify classes for ${styledElementLabel(elementKind).toLowerCase()} <${tagName}>; use primitive variants and sizes.`,
			}),
		);
		return;
	}
	for (const classToken of classResult.classTokens) {
		if (isProhibitedUtility(classToken, elementKind)) {
			findings.push(
				findingAtNode({
					ruleId: 'control-style-override',
					relativePath: record.relativePath,
					node: findingNode,
					message: `${styledElementLabel(elementKind)} class "${classToken}" belongs to an owned UI primitive.`,
				}),
			);
			continue;
		}
		const customProperties = customClassStyleProperties.get(classToken);
		if (customProperties !== undefined) {
			const prohibitedProperties = [...customProperties].filter((propertyName) =>
				isProhibitedCssProperty(propertyName, elementKind),
			);
			if (prohibitedProperties.length > 0) {
				findings.push(
					findingAtNode({
						ruleId: 'control-style-override',
						relativePath: record.relativePath,
						node: findingNode,
						message: `${styledElementLabel(elementKind)} custom class "${classToken}" owns prohibited properties: ${prohibitedProperties.toSorted().join(', ')}.`,
					}),
				);
			}
			continue;
		}
		if (!isKnownLayoutUtility(classToken) && !isRawPaletteUtility(classToken)) {
			findings.push(
				findingAtNode({
					ruleId: 'unknown-control-classes',
					relativePath: record.relativePath,
					node: findingNode,
					message: `Cannot resolve custom class "${classToken}" on ${styledElementLabel(elementKind).toLowerCase()} <${tagName}>.`,
				}),
			);
		}
	}
}

function styledElementKind(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	visited: Set<string>,
): StyledElementKind | null {
	const tagName = element.tagName.getText();
	if (['button', 'input', 'select', 'textarea'].includes(tagName)) {
		return 'control';
	}
	if (classifyJsxRole(element) === 'control') {
		return 'control';
	}
	const imports = importsForRecord(record, records);
	const binding = imports.get(tagName);
	if (binding !== undefined) {
		if (
			binding.moduleSpecifier.includes('/components/ui/') ||
			binding.moduleSpecifier.startsWith('@/components/ui/')
		) {
			return explicitStyledElementKind(binding.importedName);
		}
		if (binding.targetPath !== null) {
			const targetRecord = records.get(binding.targetPath);
			return targetRecord === undefined
				? null
				: exportedComponentStyledElementKind(records, targetRecord, binding.importedName, visited);
		}
	}
	return exportedComponentStyledElementKind(records, record, tagName, visited);
}

function exportedComponentStyledElementKind(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	componentName: string,
	visited: Set<string>,
): StyledElementKind | null {
	const key = `${record.relativePath}:${componentName}`;
	if (visited.has(key)) {
		return null;
	}
	visited.add(key);
	const declaration = findValueDeclaration(record.sourceFile, componentName);
	if (declaration === null) {
		return null;
	}
	let containedKind: StyledElementKind | null = null;
	walk(declaration, (node: ts.Node): void => {
		if (
			containedKind === null &&
			(ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) &&
			node !== declaration
		) {
			containedKind = styledElementKind(records, record, node, visited);
		}
	});
	return containedKind;
}

function checkInlineStyle(
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	elementKind: StyledElementKind,
	findings: StyleSystemFinding[],
): void {
	const styleAttribute = element.attributes.properties.find(
		(attribute): attribute is ts.JsxAttribute =>
			ts.isJsxAttribute(attribute) && attribute.name.getText() === 'style',
	);
	if (styleAttribute?.initializer === undefined) {
		return;
	}
	const styleExpression = jsxAttributeExpression(styleAttribute.initializer);
	if (styleExpression !== null) {
		checkInlineStyleExpression(record, styleExpression, styleAttribute, elementKind, findings);
	}
}

function checkInlineStyleExpression(
	record: TypeScriptSourceRecord,
	styleExpression: ts.Expression,
	findingNode: ts.Node,
	elementKind: StyledElementKind,
	findings: StyleSystemFinding[],
): void {
	const unwrappedStyleExpression = unwrapExpression(styleExpression);
	if (
		unwrappedStyleExpression === null ||
		!ts.isObjectLiteralExpression(unwrappedStyleExpression)
	) {
		findings.push(
			findingAtNode({
				ruleId: 'unknown-control-classes',
				relativePath: record.relativePath,
				node: findingNode,
				message: `Cannot statically classify inline styles for ${styledElementLabel(elementKind).toLowerCase()}.`,
			}),
		);
		return;
	}
	for (const property of unwrappedStyleExpression.properties) {
		if (!ts.isPropertyAssignment(property) && !ts.isShorthandPropertyAssignment(property)) {
			findings.push(
				findingAtNode({
					ruleId: 'unknown-control-classes',
					relativePath: record.relativePath,
					node: property,
					message: `Cannot statically classify spread or computed inline styles for ${styledElementLabel(elementKind).toLowerCase()}.`,
				}),
			);
			continue;
		}
		const propertyName = propertyNameText(property.name);
		if (propertyName !== null && isProhibitedInlineStyleProperty(propertyName, elementKind)) {
			findings.push(
				findingAtNode({
					ruleId: 'control-style-override',
					relativePath: record.relativePath,
					node: property,
					message: `${styledElementLabel(elementKind)} inline style "${propertyName}" belongs to an owned UI primitive.`,
				}),
			);
		}
	}
}

function isProhibitedCssProperty(cssPropertyName: string, elementKind: StyledElementKind): boolean {
	const camelCasePropertyName = cssPropertyName.replace(/-([a-z])/gu, (_match, letter: string) =>
		letter.toUpperCase(),
	);
	return isProhibitedInlineStyleProperty(camelCasePropertyName, elementKind);
}

function styledElementLabel(elementKind: StyledElementKind): string {
	return elementKind === 'control' ? 'Control' : 'Floating frame';
}

function importsForRecord(
	record: TypeScriptSourceRecord,
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
): ReadonlyMap<string, ImportBinding> {
	const imports = new Map<string, ImportBinding>();
	for (const statement of record.sourceFile.statements) {
		if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)) {
			continue;
		}
		const moduleSpecifier = statement.moduleSpecifier.text;
		const targetPath = resolveImportPath(record.relativePath, moduleSpecifier, records);
		const bindings = statement.importClause?.namedBindings;
		if (bindings !== undefined && ts.isNamedImports(bindings)) {
			for (const element of bindings.elements) {
				imports.set(element.name.text, {
					importedName: element.propertyName?.text ?? element.name.text,
					targetPath,
					moduleSpecifier,
				});
			}
		}
	}
	return imports;
}

function resolveImportPath(
	fromPath: string,
	moduleSpecifier: string,
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
): string | null {
	let basePath: string;
	if (moduleSpecifier.startsWith('@/')) {
		basePath = `src/${moduleSpecifier.slice(2)}`;
	} else if (moduleSpecifier.startsWith('.')) {
		basePath = normalize(join(dirname(fromPath), moduleSpecifier)).replaceAll('\\', '/');
	} else {
		return null;
	}
	const withoutRuntimeExtension = ['.js', '.jsx', '.mjs'].includes(extname(basePath))
		? basePath.slice(0, -extname(basePath).length)
		: basePath;
	for (const candidate of [
		basePath,
		`${withoutRuntimeExtension}.ts`,
		`${withoutRuntimeExtension}.tsx`,
	]) {
		if (records.has(candidate)) {
			return candidate;
		}
	}
	return null;
}

function findValueDeclaration(sourceFile: ts.SourceFile, name: string): ts.Node | null {
	for (const statement of sourceFile.statements) {
		if (ts.isFunctionDeclaration(statement) && statement.name?.text === name) {
			return statement;
		}
		if (ts.isVariableStatement(statement)) {
			for (const declaration of statement.declarationList.declarations) {
				if (ts.isIdentifier(declaration.name) && declaration.name.text === name) {
					return declaration;
				}
			}
		}
	}
	return null;
}

function jsxAttributeExpression(initializer: ts.JsxAttributeValue): ts.Expression | null {
	if (ts.isStringLiteral(initializer)) {
		return initializer;
	}
	return ts.isJsxExpression(initializer) ? (initializer.expression ?? null) : null;
}

function propertyNameText(name: ts.PropertyName): string | null {
	return ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)
		? name.text
		: null;
}

function normalizePaletteValue(value: string): string {
	return value.trim().replace(/\s+/gu, ' ').toLowerCase();
}

function isTestPath(relativePath: string): boolean {
	return /(?:^|\/)(?:test-support|tests?)(?:\/|$)|\.(?:browser\.|e2e\.|integration\.|unit\.)?test\.[cm]?[jt]sx?$/u.test(
		relativePath,
	);
}

function walk(node: ts.Node, visit: (node: ts.Node) => void): void {
	visit(node);
	node.forEachChild((child) => walk(child, visit));
}
