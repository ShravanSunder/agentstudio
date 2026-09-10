import ts from 'typescript';

import {
	explicitStyledElementKind,
	type StyledElementKind,
} from './check-bridgeweb-style-system-classification.ts';
import {
	findValueDeclaration,
	importsForRecord,
} from './check-bridgeweb-style-system-source-bindings.ts';
import { classifyJsxRole } from './check-bridgeweb-style-system-typescript-jsx-resolution.ts';
import { unwrapExpression } from './check-bridgeweb-style-system-typescript-resolution.ts';
import type { TypeScriptSourceRecord } from './check-bridgeweb-style-system-typescript.ts';

interface OwnedContentSource {
	readonly record: TypeScriptSourceRecord;
	readonly declaration: ts.Node;
}

interface OwnedContentAnalysis {
	readonly records: ReadonlyMap<string, TypeScriptSourceRecord>;
	readonly shouldInspect: (record: TypeScriptSourceRecord) => boolean;
	readonly classify: (
		record: TypeScriptSourceRecord,
		element: ts.JsxOpeningLikeElement,
	) => StyledElementKind | null;
	readonly resolve: (record: TypeScriptSourceRecord, name: string) => OwnedContentSource | null;
}

/** Carry content ownership through imported children without classifying outer layout as a control. */
export function collectOwnedContentScopes(props: OwnedContentAnalysis): ReadonlySet<ts.Node> {
	const scopes = new Set<ts.Node>();
	let changed = true;
	while (changed) {
		changed = false;
		for (const record of props.records.values()) {
			if (record.relativePath.startsWith('src/components/ui/') || !props.shouldInspect(record))
				continue;
			walk(record.sourceFile, (node): void => {
				if (!ts.isJsxOpeningElement(node) && !ts.isJsxSelfClosingElement(node)) return;
				if (
					!isOwnedContent({
						element: node,
						scopes,
						classify: (ancestor) => props.classify(record, ancestor),
					})
				)
					return;
				const target = props.resolve(record, node.tagName.getText());
				if (
					target === null ||
					target.record.relativePath.startsWith('src/components/ui/') ||
					scopes.has(target.declaration)
				)
					return;
				scopes.add(target.declaration);
				changed = true;
			});
		}
	}
	return scopes;
}

export function isOwnedContent(props: {
	readonly element: ts.JsxOpeningLikeElement;
	readonly scopes: ReadonlySet<ts.Node>;
	readonly classify: (element: ts.JsxOpeningLikeElement) => StyledElementKind | null;
}): boolean {
	let ancestor: ts.Node | undefined = props.element.parent;
	while (ancestor !== undefined) {
		if (props.scopes.has(ancestor)) return true;
		if (
			ts.isJsxElement(ancestor) &&
			ancestor.openingElement !== props.element &&
			props.classify(ancestor.openingElement) === 'control'
		)
			return true;
		ancestor = ancestor.parent;
	}
	return false;
}

/** Only a component's returned root owns caller layout; nested controls do not. */
export function returnedElementKinds(props: {
	readonly declaration: ts.Node;
	readonly classify: (element: ts.JsxOpeningLikeElement) => StyledElementKind | null;
}): StyledElementKind | null {
	let result: StyledElementKind | null = null;
	const inspectExpression = (expression: ts.Expression): void => {
		if (
			ts.isParenthesizedExpression(expression) ||
			ts.isAsExpression(expression) ||
			ts.isSatisfiesExpression(expression)
		)
			inspectExpression(expression.expression);
		else if (ts.isJsxElement(expression)) result ??= props.classify(expression.openingElement);
		else if (ts.isJsxSelfClosingElement(expression)) result ??= props.classify(expression);
		else if (ts.isConditionalExpression(expression)) {
			inspectExpression(expression.whenTrue);
			inspectExpression(expression.whenFalse);
		}
	};
	const visit = (node: ts.Node): void => {
		if (
			node !== props.declaration &&
			(ts.isFunctionDeclaration(node) || ts.isFunctionExpression(node) || ts.isArrowFunction(node))
		) {
			if (!ts.isVariableDeclaration(props.declaration) || props.declaration.initializer !== node)
				return;
		}
		if (ts.isReturnStatement(node) && node.expression !== undefined)
			inspectExpression(node.expression);
		if (ts.isArrowFunction(node) && !ts.isBlock(node.body)) inspectExpression(node.body);
		node.forEachChild(visit);
	};
	visit(props.declaration);
	return result;
}

export type StylingDestination = StyledElementKind | 'layout' | 'unknown' | 'unused';

/** Summarize one caller styling prop by following only explicit JSX forwarding edges. */
export function stylingPropDestination(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	propName: string,
	visited: Set<string>,
): StylingDestination {
	const directKind = directStyledElementKind(records, record, element);
	if (directKind !== null) return directKind;
	const tagName = element.tagName.getText();
	if (/^[a-z]/u.test(tagName)) return 'layout';
	const imports = importsForRecord(record, records);
	const importRootName = tagName.split('.').at(0) ?? tagName;
	const binding = imports.get(tagName) ?? imports.get(importRootName);
	if (binding !== undefined) {
		if (binding.targetPath === null) {
			return isLocalModuleSpecifier(binding.moduleSpecifier) ? 'unknown' : 'layout';
		}
		if (importRootName !== tagName && imports.get(tagName) === undefined) return 'unknown';
		const targetRecord = records.get(binding.targetPath);
		return targetRecord === undefined
			? 'unknown'
			: componentPropDestination(records, targetRecord, binding.importedName, propName, visited);
	}
	const finiteAliasDestination = finiteIntrinsicAliasDestination(record, element, tagName);
	if (finiteAliasDestination !== null) return finiteAliasDestination;
	return componentPropDestination(records, record, tagName, propName, visited);
}

export function hasOwnedStyledDescendant(props: {
	readonly element: ts.JsxOpeningLikeElement;
	readonly record: TypeScriptSourceRecord;
	readonly records: ReadonlyMap<string, TypeScriptSourceRecord>;
	readonly classify: (
		record: TypeScriptSourceRecord,
		element: ts.JsxOpeningLikeElement,
	) => StyledElementKind | null;
}): boolean {
	const jsxElement = ts.isJsxOpeningElement(props.element) ? props.element.parent : props.element;
	let found = false;
	const visitedComponents = new Set<string>();
	const inspect = (record: TypeScriptSourceRecord, root: ts.Node, skipNode?: ts.Node): void => {
		walk(root, (node): void => {
			if (
				found ||
				node === skipNode ||
				(!ts.isJsxOpeningElement(node) && !ts.isJsxSelfClosingElement(node))
			)
				return;
			if (props.classify(record, node) !== null) {
				found = true;
				return;
			}
			const source = resolveComponentSource(props.records, record, node.tagName.getText());
			if (source === null || visitedComponents.has(source.key)) return;
			visitedComponents.add(source.key);
			inspect(source.record, source.declaration);
		});
	};
	inspect(props.record, jsxElement, props.element);
	return found;
}

function resolveComponentSource(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	componentName: string,
): {
	readonly key: string;
	readonly record: TypeScriptSourceRecord;
	readonly declaration: ts.Node;
} | null {
	if (/^[a-z]/u.test(componentName)) return null;
	const binding = importsForRecord(record, records).get(componentName);
	const targetRecord =
		binding?.targetPath === null || binding?.targetPath === undefined
			? record
			: records.get(binding.targetPath);
	if (targetRecord === undefined) return null;
	const resolvedName = binding?.importedName ?? componentName;
	const declaration = findValueDeclaration(targetRecord.sourceFile, resolvedName);
	return declaration === null
		? null
		: {
				key: `${targetRecord.relativePath}:${resolvedName}`,
				record: targetRecord,
				declaration,
			};
}

function componentPropDestination(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	componentName: string,
	propName: string,
	visited: Set<string>,
): StylingDestination {
	const key = `${record.relativePath}:${componentName}:${propName}`;
	if (visited.has(key)) return 'unknown';
	const nextVisited = new Set(visited).add(key);
	const explicitKind = explicitStyledElementKind(componentName);
	if (explicitKind !== null && record.relativePath.startsWith('src/components/ui/')) {
		return explicitKind;
	}
	const declaration = findValueDeclaration(record.sourceFile, componentName);
	if (declaration === null) return 'unknown';
	if (ts.isVariableDeclaration(declaration)) {
		const initializer = unwrapExpression(declaration.initializer);
		if (
			initializer !== null &&
			(ts.isIdentifier(initializer) || ts.isPropertyAccessExpression(initializer))
		) {
			const aliasName = initializer.getText();
			const aliasBinding = importsForRecord(record, records).get(aliasName);
			if (aliasBinding?.targetPath !== null && aliasBinding?.targetPath !== undefined) {
				const targetRecord = records.get(aliasBinding.targetPath);
				return targetRecord === undefined
					? 'unknown'
					: componentPropDestination(
							records,
							targetRecord,
							aliasBinding.importedName,
							propName,
							nextVisited,
						);
			}
			const aliasKind = explicitStyledElementKind(aliasName);
			return (
				aliasKind ?? componentPropDestination(records, record, aliasName, propName, nextVisited)
			);
		}
	}
	const componentFunction = componentFunctionLike(declaration);
	if (componentFunction === null) return 'unknown';
	const parameter = componentFunction.parameters.at(0);
	if (parameter === undefined) return 'unused';
	const reference = propReference(parameter, propName);
	if (reference === null) return 'unused';
	const destinations: StylingDestination[] = [];
	walk(declaration, (node): void => {
		if (!ts.isJsxOpeningElement(node) && !ts.isJsxSelfClosingElement(node)) return;
		for (const attribute of node.attributes.properties) {
			if (ts.isJsxAttribute(attribute)) {
				const expression = jsxAttributeExpression(attribute.initializer);
				if (
					expression === null ||
					!expressionReferencesProp(declaration, expression, reference, new Set())
				)
					continue;
				const forwardedPropName = attribute.name.getText();
				if (/^[a-z]/u.test(node.tagName.getText()) && forwardedPropName !== propName) {
					destinations.push('unknown');
				} else {
					destinations.push(
						stylingPropDestination(records, record, node, forwardedPropName, nextVisited),
					);
				}
			} else if (
				expressionReferencesProp(declaration, attribute.expression, reference, new Set())
			) {
				destinations.push(stylingPropDestination(records, record, node, propName, nextVisited));
			}
		}
	});
	return mergeStylingDestinations(destinations);
}

interface PropReference {
	readonly propName: string;
	readonly objectName: string | null;
	readonly localNames: ReadonlySet<string>;
}

function componentFunctionLike(
	declaration: ts.Node,
): ts.FunctionDeclaration | ts.FunctionExpression | ts.ArrowFunction | null {
	if (ts.isFunctionDeclaration(declaration)) return declaration;
	if (!ts.isVariableDeclaration(declaration)) return null;
	const initializer = unwrapExpression(declaration.initializer);
	if (initializer === null) return null;
	if (ts.isArrowFunction(initializer) || ts.isFunctionExpression(initializer)) return initializer;
	if (!ts.isCallExpression(initializer)) return null;
	const wrapperName = initializer.expression.getText();
	if (!['memo', 'React.memo', 'forwardRef', 'React.forwardRef'].includes(wrapperName)) return null;
	const callback = unwrapExpression(initializer.arguments.at(0));
	return callback !== null && (ts.isArrowFunction(callback) || ts.isFunctionExpression(callback))
		? callback
		: null;
}

function propReference(parameter: ts.ParameterDeclaration, propName: string): PropReference | null {
	if (ts.isIdentifier(parameter.name)) {
		return { propName, objectName: parameter.name.text, localNames: new Set() };
	}
	if (!ts.isObjectBindingPattern(parameter.name)) return null;
	const localNames = new Set<string>();
	let explicitlyExcluded = false;
	for (const element of parameter.name.elements) {
		const sourceName = element.propertyName ?? element.name;
		if (
			element.dotDotDotToken === undefined &&
			(ts.isIdentifier(sourceName) || ts.isStringLiteralLike(sourceName)) &&
			sourceName.text === propName
		) {
			explicitlyExcluded = true;
			if (ts.isIdentifier(element.name)) localNames.add(element.name.text);
		}
	}
	if (!explicitlyExcluded) {
		for (const element of parameter.name.elements) {
			if (element.dotDotDotToken !== undefined && ts.isIdentifier(element.name)) {
				localNames.add(element.name.text);
			}
		}
	}
	return localNames.size === 0 ? null : { propName, objectName: null, localNames };
}

function expressionReferencesProp(
	declaration: ts.Node,
	expression: ts.Expression,
	reference: PropReference,
	visitedVariables: Set<string>,
): boolean {
	if (
		ts.isIdentifier(expression) &&
		reference.objectName !== null &&
		expression.text === reference.objectName
	) {
		return true;
	}
	let found = false;
	const visit = (node: ts.Node): void => {
		if (found) return;
		if (
			ts.isPropertyAccessExpression(node) &&
			reference.objectName !== null &&
			ts.isIdentifier(node.expression) &&
			node.expression.text === reference.objectName &&
			node.name.text === reference.propName
		) {
			found = true;
			return;
		}
		if (
			ts.isElementAccessExpression(node) &&
			reference.objectName !== null &&
			ts.isIdentifier(node.expression) &&
			node.expression.text === reference.objectName &&
			node.argumentExpression !== undefined &&
			ts.isStringLiteralLike(node.argumentExpression) &&
			node.argumentExpression.text === reference.propName
		) {
			found = true;
			return;
		}
		if (ts.isIdentifier(node) && reference.localNames.has(node.text)) {
			found = true;
			return;
		}
		if (
			ts.isSpreadAssignment(node) &&
			ts.isIdentifier(node.expression) &&
			reference.objectName !== null &&
			node.expression.text === reference.objectName
		) {
			found = true;
			return;
		}
		if (ts.isIdentifier(node) && !visitedVariables.has(node.text)) {
			const initializer = findVariableInitializerWithin(declaration, node.text);
			if (initializer !== null) {
				visitedVariables.add(node.text);
				if (expressionReferencesProp(declaration, initializer, reference, visitedVariables)) {
					found = true;
					return;
				}
			}
		}
		node.forEachChild(visit);
	};
	visit(expression);
	return found;
}

function findVariableInitializerWithin(declaration: ts.Node, name: string): ts.Expression | null {
	let result: ts.Expression | null = null;
	walk(declaration, (node): void => {
		if (
			result === null &&
			ts.isVariableDeclaration(node) &&
			ts.isIdentifier(node.name) &&
			node.name.text === name
		) {
			result = node.initializer ?? null;
		}
	});
	return result;
}

function mergeStylingDestinations(destinations: readonly StylingDestination[]): StylingDestination {
	if (destinations.includes('unknown')) return 'unknown';
	if (destinations.includes('control')) return 'control';
	if (destinations.includes('floating-frame')) return 'floating-frame';
	if (destinations.includes('layout')) return 'layout';
	return 'unused';
}

function directStyledElementKind(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
): StyledElementKind | null {
	const tagName = element.tagName.getText();
	if (['button', 'input', 'select', 'textarea'].includes(tagName)) return 'control';
	if (classifyJsxRole(element) === 'control') return 'control';
	const binding = importsForRecord(record, records).get(tagName);
	if (
		binding !== undefined &&
		(binding.moduleSpecifier.includes('/components/ui/') ||
			binding.moduleSpecifier.startsWith('@/components/ui/'))
	) {
		return explicitStyledElementKind(binding.importedName);
	}
	return explicitStyledElementKind(tagName);
}

function finiteIntrinsicAliasDestination(
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	aliasName: string,
): StylingDestination | null {
	const declaration = findEnclosingVariableDeclaration(element, aliasName);
	if (declaration?.initializer === undefined) return null;
	const tagNames = finiteIntrinsicTagNames(record, declaration.initializer, declaration, new Set());
	if (tagNames === null || tagNames.size === 0) return null;
	return [...tagNames].some((tagName) =>
		['button', 'input', 'select', 'textarea'].includes(tagName),
	)
		? 'control'
		: 'layout';
}

function finiteIntrinsicTagNames(
	record: TypeScriptSourceRecord,
	expression: ts.Expression,
	scope: ts.Node,
	visited: Set<string>,
): ReadonlySet<string> | null {
	const unwrapped = unwrapExpression(expression);
	if (unwrapped === null) return null;
	if (ts.isStringLiteralLike(unwrapped)) {
		return /^[a-z][a-z\d-]*$/u.test(unwrapped.text) ? new Set([unwrapped.text]) : null;
	}
	if (
		ts.isBinaryExpression(unwrapped) &&
		(unwrapped.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken ||
			unwrapped.operatorToken.kind === ts.SyntaxKind.BarBarToken)
	) {
		return mergeFiniteTagNames([
			finiteIntrinsicTagNames(record, unwrapped.left, scope, visited),
			finiteIntrinsicTagNames(record, unwrapped.right, scope, visited),
		]);
	}
	if (ts.isConditionalExpression(unwrapped)) {
		return mergeFiniteTagNames([
			finiteIntrinsicTagNames(record, unwrapped.whenTrue, scope, visited),
			finiteIntrinsicTagNames(record, unwrapped.whenFalse, scope, visited),
		]);
	}
	if (ts.isPropertyAccessExpression(unwrapped) && ts.isIdentifier(unwrapped.expression)) {
		const objectName = unwrapped.expression.text;
		const parameter = findEnclosingFunction(scope)?.parameters.find(
			(candidate) => ts.isIdentifier(candidate.name) && candidate.name.text === objectName,
		);
		if (parameter?.type === undefined) return null;
		const propertyType = propertyTypeForParameter(
			record.sourceFile,
			parameter.type,
			unwrapped.name.text,
		);
		return propertyType === null ? null : finiteTagNamesFromType(propertyType);
	}
	if (ts.isIdentifier(unwrapped)) {
		if (visited.has(unwrapped.text)) return null;
		visited.add(unwrapped.text);
		const declaration = findEnclosingVariableDeclaration(scope, unwrapped.text);
		return declaration?.initializer === undefined
			? null
			: finiteIntrinsicTagNames(record, declaration.initializer, declaration, visited);
	}
	return null;
}

function propertyTypeForParameter(
	sourceFile: ts.SourceFile,
	typeNode: ts.TypeNode,
	propertyName: string,
): ts.TypeNode | null {
	if (ts.isTypeLiteralNode(typeNode))
		return propertyTypeFromMembers(typeNode.members, propertyName);
	if (!ts.isTypeReferenceNode(typeNode) || !ts.isIdentifier(typeNode.typeName)) return null;
	for (const statement of sourceFile.statements) {
		if (ts.isInterfaceDeclaration(statement) && statement.name.text === typeNode.typeName.text) {
			return propertyTypeFromMembers(statement.members, propertyName);
		}
		if (ts.isTypeAliasDeclaration(statement) && statement.name.text === typeNode.typeName.text) {
			return propertyTypeForParameter(sourceFile, statement.type, propertyName);
		}
	}
	return null;
}

function propertyTypeFromMembers(
	members: ts.NodeArray<ts.TypeElement>,
	propertyName: string,
): ts.TypeNode | null {
	const property = members.find(
		(member): member is ts.PropertySignature =>
			ts.isPropertySignature(member) &&
			member.name !== undefined &&
			(ts.isIdentifier(member.name) || ts.isStringLiteralLike(member.name)) &&
			member.name.text === propertyName,
	);
	return property?.type ?? null;
}

function finiteTagNamesFromType(typeNode: ts.TypeNode): ReadonlySet<string> | null {
	if (ts.isLiteralTypeNode(typeNode) && ts.isStringLiteralLike(typeNode.literal)) {
		return /^[a-z][a-z\d-]*$/u.test(typeNode.literal.text)
			? new Set([typeNode.literal.text])
			: null;
	}
	if (!ts.isUnionTypeNode(typeNode)) return null;
	return mergeFiniteTagNames(typeNode.types.map(finiteTagNamesFromType));
}

function mergeFiniteTagNames(
	groups: readonly (ReadonlySet<string> | null)[],
): ReadonlySet<string> | null {
	if (groups.some((group) => group === null)) return null;
	return new Set(groups.flatMap((group) => [...(group ?? [])]));
}

function findEnclosingVariableDeclaration(
	node: ts.Node,
	name: string,
): ts.VariableDeclaration | null {
	const searchRoot = findEnclosingFunction(node) ?? node.getSourceFile();
	let result: ts.VariableDeclaration | null = null;
	walk(searchRoot, (candidate): void => {
		if (
			result === null &&
			ts.isVariableDeclaration(candidate) &&
			ts.isIdentifier(candidate.name) &&
			candidate.name.text === name
		) {
			result = candidate;
		}
	});
	return result;
}

function findEnclosingFunction(node: ts.Node): ts.SignatureDeclaration | null {
	let ancestor: ts.Node | undefined = node.parent;
	while (ancestor !== undefined) {
		if (ts.isFunctionLike(ancestor)) return ancestor;
		ancestor = ancestor.parent;
	}
	return null;
}

function isLocalModuleSpecifier(moduleSpecifier: string): boolean {
	return moduleSpecifier.startsWith('.') || moduleSpecifier.startsWith('@/');
}

function jsxAttributeExpression(
	initializer: ts.JsxAttributeValue | undefined,
): ts.Expression | null {
	if (initializer === undefined) return null;
	if (ts.isStringLiteral(initializer)) return initializer;
	return ts.isJsxExpression(initializer) ? (initializer.expression ?? null) : null;
}

function walk(node: ts.Node, visit: (node: ts.Node) => void): void {
	visit(node);
	node.forEachChild((child) => walk(child, visit));
}
