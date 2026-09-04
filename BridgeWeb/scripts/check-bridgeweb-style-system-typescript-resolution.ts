import { dirname, extname, join, normalize } from 'node:path';

import ts from 'typescript';

import type { TypeScriptSourceRecord } from './check-bridgeweb-style-system-typescript.ts';

export interface StaticClassResult {
	readonly classTokens: readonly string[];
	readonly unknown: boolean;
}

export interface StaticTextResult {
	readonly fragments: readonly string[];
	readonly unknown: boolean;
}

export function resolveStaticClasses(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	expression: ts.Expression,
	visited: Set<string>,
): StaticClassResult {
	const unwrapped = unwrapExpression(expression);
	if (unwrapped === null) {
		return { classTokens: [], unknown: true };
	}
	if (ts.isStringLiteralLike(unwrapped)) {
		return { classTokens: splitClassTokens(unwrapped.text), unknown: false };
	}
	if (ts.isTemplateExpression(unwrapped)) {
		const parts = [splitClassTokens(unwrapped.head.text)];
		let unknown = false;
		for (const span of unwrapped.templateSpans) {
			const resolved = resolveStaticClasses(records, record, span.expression, visited);
			parts.push(resolved.classTokens, splitClassTokens(span.literal.text));
			unknown ||= resolved.unknown;
		}
		return { classTokens: parts.flat(), unknown };
	}
	if (ts.isIdentifier(unwrapped)) {
		return resolveIdentifierClasses(records, record, unwrapped, visited);
	}
	if (ts.isConditionalExpression(unwrapped)) {
		return mergeStaticClassResults([
			resolveStaticClasses(records, record, unwrapped.whenTrue, visited),
			resolveStaticClasses(records, record, unwrapped.whenFalse, visited),
		]);
	}
	if (ts.isBinaryExpression(unwrapped)) {
		if (
			unwrapped.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken ||
			unwrapped.operatorToken.kind === ts.SyntaxKind.BarBarToken ||
			unwrapped.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken
		) {
			return resolveStaticClasses(records, record, unwrapped.right, visited);
		}
		if (unwrapped.operatorToken.kind === ts.SyntaxKind.PlusToken) {
			return mergeStaticClassResults([
				resolveStaticClasses(records, record, unwrapped.left, visited),
				resolveStaticClasses(records, record, unwrapped.right, visited),
			]);
		}
	}
	if (ts.isCallExpression(unwrapped) && ts.isIdentifier(unwrapped.expression)) {
		if (['cn', 'clsx'].includes(unwrapped.expression.text)) {
			return mergeStaticClassResults(
				unwrapped.arguments.map((argument) =>
					resolveStaticClasses(records, record, argument, visited),
				),
			);
		}
		if (unwrapped.expression.text === 'cva') {
			return resolveCvaClasses(records, record, unwrapped.arguments, visited);
		}
		const initializer = findVariableInitializer(record.sourceFile, unwrapped.expression.text);
		const resolvedInitializer = initializer === null ? null : unwrapExpression(initializer);
		if (
			resolvedInitializer !== null &&
			ts.isCallExpression(resolvedInitializer) &&
			ts.isIdentifier(resolvedInitializer.expression) &&
			resolvedInitializer.expression.text === 'cva'
		) {
			return resolveCvaClasses(records, record, resolvedInitializer.arguments, visited);
		}
	}
	if (ts.isArrayLiteralExpression(unwrapped)) {
		return mergeStaticClassResults(
			unwrapped.elements.map((element) => resolveStaticClasses(records, record, element, visited)),
		);
	}
	if (ts.isObjectLiteralExpression(unwrapped)) {
		return mergeStaticClassResults(
			unwrapped.properties.map((property): StaticClassResult => {
				if (!ts.isPropertyAssignment(property)) {
					return { classTokens: [], unknown: true };
				}
				const propertyName = propertyNameText(property.name);
				return propertyName === null
					? { classTokens: [], unknown: true }
					: { classTokens: splitClassTokens(propertyName), unknown: false };
			}),
		);
	}
	return { classTokens: [], unknown: true };
}

export function resolveStaticTextFragments(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	expression: ts.Expression,
	visited: Set<string>,
): StaticTextResult {
	const unwrapped = unwrapExpression(expression);
	if (unwrapped === null) return { fragments: [], unknown: true };
	if (ts.isStringLiteralLike(unwrapped)) {
		return { fragments: [unwrapped.text], unknown: false };
	}
	if (ts.isTemplateExpression(unwrapped)) {
		const fragments = [unwrapped.head.text];
		let unknown = false;
		for (const span of unwrapped.templateSpans) {
			const resolved = resolveStaticTextFragments(records, record, span.expression, visited);
			fragments.push(...resolved.fragments, span.literal.text);
			unknown ||= resolved.unknown;
		}
		return { fragments, unknown };
	}
	if (ts.isIdentifier(unwrapped)) {
		const key = `${record.relativePath}:${unwrapped.text}`;
		if (visited.has(key)) return { fragments: [], unknown: true };
		visited.add(key);
		const initializer = findVariableInitializer(record.sourceFile, unwrapped.text);
		if (initializer !== null) {
			return resolveStaticTextFragments(records, record, initializer, visited);
		}
		const binding = importsForRecord(record, records).get(unwrapped.text);
		if (binding?.targetPath !== null && binding?.targetPath !== undefined) {
			const targetRecord = records.get(binding.targetPath);
			const targetExpression =
				targetRecord === undefined
					? null
					: findVariableInitializer(targetRecord.sourceFile, binding.importedName);
			if (targetRecord !== undefined && targetExpression !== null) {
				return resolveStaticTextFragments(records, targetRecord, targetExpression, visited);
			}
		}
		return { fragments: [], unknown: true };
	}
	if (ts.isPropertyAccessExpression(unwrapped) || ts.isElementAccessExpression(unwrapped)) {
		const propertyName = ts.isPropertyAccessExpression(unwrapped)
			? unwrapped.name.text
			: unwrapped.argumentExpression !== undefined &&
				  ts.isStringLiteralLike(unwrapped.argumentExpression)
				? unwrapped.argumentExpression.text
				: null;
		if (propertyName === null) return { fragments: [], unknown: true };
		const property = resolveStaticObjectProperty(
			records,
			record,
			unwrapped.expression,
			propertyName,
		);
		return property === null
			? { fragments: [], unknown: true }
			: resolveStaticTextFragments(records, property.record, property.expression, visited);
	}
	if (ts.isConditionalExpression(unwrapped)) {
		return mergeStaticTextResults([
			resolveStaticTextFragments(records, record, unwrapped.whenTrue, visited),
			resolveStaticTextFragments(records, record, unwrapped.whenFalse, visited),
		]);
	}
	if (ts.isBinaryExpression(unwrapped)) {
		if (unwrapped.operatorToken.kind === ts.SyntaxKind.PlusToken) {
			return mergeStaticTextResults([
				resolveStaticTextFragments(records, record, unwrapped.left, visited),
				resolveStaticTextFragments(records, record, unwrapped.right, visited),
			]);
		}
		if (
			unwrapped.operatorToken.kind === ts.SyntaxKind.BarBarToken ||
			unwrapped.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken
		) {
			return mergeStaticTextResults([
				resolveStaticTextFragments(records, record, unwrapped.left, visited),
				resolveStaticTextFragments(records, record, unwrapped.right, visited),
			]);
		}
	}
	return { fragments: [], unknown: true };
}

function resolveStaticObjectProperty(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	objectExpression: ts.Expression,
	propertyName: string,
): { readonly record: TypeScriptSourceRecord; readonly expression: ts.Expression } | null {
	const unwrappedObject = unwrapExpression(objectExpression);
	if (unwrappedObject === null) return null;
	if (ts.isObjectLiteralExpression(unwrappedObject)) {
		const property = unwrappedObject.properties.find(
			(candidate): candidate is ts.PropertyAssignment =>
				ts.isPropertyAssignment(candidate) && propertyNameText(candidate.name) === propertyName,
		);
		return property === undefined ? null : { record, expression: property.initializer };
	}
	if (!ts.isIdentifier(unwrappedObject)) return null;
	const localInitializer = findVariableInitializer(record.sourceFile, unwrappedObject.text);
	if (localInitializer !== null) {
		return resolveStaticObjectProperty(records, record, localInitializer, propertyName);
	}
	const binding = importsForRecord(record, records).get(unwrappedObject.text);
	if (binding?.targetPath === null || binding?.targetPath === undefined) return null;
	const targetRecord = records.get(binding.targetPath);
	if (targetRecord === undefined) return null;
	const targetInitializer = findVariableInitializer(targetRecord.sourceFile, binding.importedName);
	return targetInitializer === null
		? null
		: resolveStaticObjectProperty(records, targetRecord, targetInitializer, propertyName);
}

export function unwrapExpression(expression: ts.Expression | undefined): ts.Expression | null {
	let current = expression;
	while (
		current !== undefined &&
		(ts.isAsExpression(current) ||
			ts.isSatisfiesExpression(current) ||
			ts.isParenthesizedExpression(current) ||
			ts.isTypeAssertionExpression(current) ||
			ts.isNonNullExpression(current))
	) {
		current = current.expression;
	}
	return current ?? null;
}

export function splitClassTokens(value: string): readonly string[] {
	return value.trim().split(/\s+/u).filter(Boolean);
}

function resolveIdentifierClasses(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	identifier: ts.Identifier,
	visited: Set<string>,
): StaticClassResult {
	const key = `${record.relativePath}:${identifier.text}`;
	if (visited.has(key)) {
		return { classTokens: [], unknown: true };
	}
	visited.add(key);
	const declaration = findVariableInitializer(record.sourceFile, identifier.text);
	if (declaration !== null) {
		return resolveStaticClasses(records, record, declaration, visited);
	}
	const binding = importsForRecord(record, records).get(identifier.text);
	if (binding?.targetPath !== null && binding?.targetPath !== undefined) {
		const targetRecord = records.get(binding.targetPath);
		const targetExpression =
			targetRecord === undefined
				? null
				: findVariableInitializer(targetRecord.sourceFile, binding.importedName);
		if (targetRecord !== undefined && targetExpression !== null) {
			return resolveStaticClasses(records, targetRecord, targetExpression, visited);
		}
	}
	return { classTokens: [], unknown: true };
}

function importsForRecord(
	record: TypeScriptSourceRecord,
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
): ReadonlyMap<string, { readonly importedName: string; readonly targetPath: string | null }> {
	const imports = new Map<
		string,
		{ readonly importedName: string; readonly targetPath: string | null }
	>();
	for (const statement of record.sourceFile.statements) {
		if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)) {
			continue;
		}
		const targetPath = resolveImportPath(
			record.relativePath,
			statement.moduleSpecifier.text,
			records,
		);
		const bindings = statement.importClause?.namedBindings;
		if (bindings !== undefined && ts.isNamedImports(bindings)) {
			for (const element of bindings.elements) {
				imports.set(element.name.text, {
					importedName: element.propertyName?.text ?? element.name.text,
					targetPath,
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

function findVariableInitializer(sourceFile: ts.SourceFile, name: string): ts.Expression | null {
	for (const statement of sourceFile.statements) {
		if (!ts.isVariableStatement(statement)) {
			continue;
		}
		for (const declaration of statement.declarationList.declarations) {
			if (ts.isIdentifier(declaration.name) && declaration.name.text === name) {
				return declaration.initializer ?? null;
			}
		}
	}
	return null;
}

function mergeStaticClassResults(results: readonly StaticClassResult[]): StaticClassResult {
	return {
		classTokens: results.flatMap(({ classTokens }) => classTokens),
		unknown: results.some(({ unknown }) => unknown),
	};
}

function resolveCvaClasses(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	argumentsList: readonly ts.Expression[],
	visited: Set<string>,
): StaticClassResult {
	const results: StaticClassResult[] = [];
	const collect = (node: ts.Node): void => {
		if (ts.isStringLiteralLike(node)) {
			results.push({ classTokens: splitClassTokens(node.text), unknown: false });
			return;
		}
		if (ts.isTemplateExpression(node)) {
			results.push(resolveStaticClasses(records, record, node, visited));
			return;
		}
		if (ts.isPropertyAssignment(node)) {
			collect(node.initializer);
			return;
		}
		if (ts.isShorthandPropertyAssignment(node) || ts.isSpreadAssignment(node)) {
			results.push({ classTokens: [], unknown: true });
			return;
		}
		node.forEachChild(collect);
	};
	for (const argument of argumentsList) collect(argument);
	return mergeStaticClassResults(results);
}

function mergeStaticTextResults(results: readonly StaticTextResult[]): StaticTextResult {
	return {
		fragments: results.flatMap(({ fragments }) => fragments),
		unknown: results.some(({ unknown }) => unknown),
	};
}

function propertyNameText(name: ts.PropertyName): string | null {
	return ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)
		? name.text
		: null;
}
