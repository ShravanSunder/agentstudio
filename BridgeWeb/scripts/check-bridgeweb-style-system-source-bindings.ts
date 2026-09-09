import { dirname, extname, join, normalize } from 'node:path';

import ts from 'typescript';

import type { TypeScriptSourceRecord } from './check-bridgeweb-style-system-typescript.ts';

interface ImportBinding {
	readonly importedName: string;
	readonly targetPath: string | null;
	readonly moduleSpecifier: string;
}

export function importsForRecord(
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
		if (bindings !== undefined && ts.isNamespaceImport(bindings)) {
			const namespace = bindings.name.text;
			walk(record.sourceFile, (node): void => {
				if (ts.isPropertyAccessExpression(node) && node.expression.getText() === namespace) {
					imports.set(node.getText(), {
						importedName: node.name.text,
						targetPath,
						moduleSpecifier,
					});
				}
			});
		}
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

export function findValueDeclaration(sourceFile: ts.SourceFile, name: string): ts.Node | null {
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

function walk(node: ts.Node, visit: (node: ts.Node) => void): void {
	visit(node);
	node.forEachChild((child) => walk(child, visit));
}
