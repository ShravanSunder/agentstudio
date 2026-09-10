import ts from 'typescript';

import { unwrapExpression } from './check-bridgeweb-style-system-typescript-resolution.ts';
import type { TypeScriptSourceRecord } from './check-bridgeweb-style-system-typescript.ts';

export interface JsxStylingSpreadResolution {
	readonly classExpressions: readonly ts.Expression[];
	readonly styleExpressions: readonly ts.Expression[];
	readonly unknownStyling: boolean;
}

type StylingPropertyName = 'className' | 'style';
const allStylingPropertyNames = new Set<StylingPropertyName>(['className', 'style']);

const controlRoles = new Set([
	'button',
	'checkbox',
	'menuitem',
	'menuitemcheckbox',
	'menuitemradio',
	'option',
	'radio',
	'switch',
	'tab',
]);

export function classifyJsxRole(
	element: ts.JsxOpeningLikeElement,
): 'control' | 'other' | 'unknown' {
	const roleAttribute = element.attributes.properties.find(
		(attribute): attribute is ts.JsxAttribute =>
			ts.isJsxAttribute(attribute) && attribute.name.getText() === 'role',
	);
	if (roleAttribute === undefined) {
		return 'other';
	}
	const expression = jsxAttributeExpression(roleAttribute.initializer);
	const value = expression === null ? null : staticStringValue(expression);
	if (value === null) {
		return 'unknown';
	}
	return controlRoles.has(value) ? 'control' : 'other';
}

export function resolveJsxStylingSpreads(
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
): JsxStylingSpreadResolution {
	return mergeSpreadResolutions(
		element.attributes.properties
			.filter(ts.isJsxSpreadAttribute)
			.map((attribute) => resolveSpreadExpression(record, attribute.expression, new Set())),
	);
}

function resolveSpreadExpression(
	record: TypeScriptSourceRecord,
	expression: ts.Expression,
	visited: Set<string>,
): JsxStylingSpreadResolution {
	const unwrapped = unwrapExpression(expression);
	if (unwrapped === null) {
		return unknownSpread();
	}
	if (ts.isObjectLiteralExpression(unwrapped)) {
		const classExpressions: ts.Expression[] = [];
		const styleExpressions: ts.Expression[] = [];
		let unknownStyling = false;
		for (const property of unwrapped.properties) {
			if (ts.isSpreadAssignment(property)) {
				const nested = resolveSpreadExpression(record, property.expression, visited);
				classExpressions.push(...nested.classExpressions);
				styleExpressions.push(...nested.styleExpressions);
				unknownStyling ||= nested.unknownStyling;
				continue;
			}
			if (!ts.isPropertyAssignment(property)) {
				unknownStyling = true;
				continue;
			}
			const name = propertyNameText(property.name);
			if (name === null) {
				unknownStyling = true;
				continue;
			}
			if (name === 'className') {
				classExpressions.push(property.initializer);
			} else if (name === 'style') {
				styleExpressions.push(property.initializer);
			}
		}
		return { classExpressions, styleExpressions, unknownStyling };
	}
	if (ts.isIdentifier(unwrapped)) {
		if (visited.has(unwrapped.text)) {
			return unknownSpread();
		}
		visited.add(unwrapped.text);
		const initializer = findVariableInitializer(record.sourceFile, unwrapped.text);
		if (initializer !== null) {
			return resolveSpreadExpression(record, initializer, visited);
		}
		const restBinding = findRestBinding(unwrapped, unwrapped.text);
		if (restBinding !== null && ts.isIdentifier(restBinding.sourceExpression)) {
			const parameter = findEnclosingParameter(
				restBinding.sourceExpression,
				restBinding.sourceExpression.text,
			);
			if (parameter?.type !== undefined) {
				const possibleStylingProperties = stylingPropertiesForTypeNode(
					record.sourceFile,
					parameter.type,
					new Set(),
				);
				for (const excludedName of restBinding.excludedNames) {
					possibleStylingProperties.delete(excludedName as StylingPropertyName);
				}
				return possibleStylingProperties.size === 0
					? { classExpressions: [], styleExpressions: [], unknownStyling: false }
					: unknownSpread();
			}
		}
		const parameter = findEnclosingParameter(unwrapped, unwrapped.text);
		return parameter?.type === undefined
			? unknownSpread()
			: stylingPropertiesForTypeNode(record.sourceFile, parameter.type, new Set()).size === 0
				? { classExpressions: [], styleExpressions: [], unknownStyling: false }
				: unknownSpread();
	}
	return unknownSpread();
}

function stylingPropertiesForTypeNode(
	sourceFile: ts.SourceFile,
	typeNode: ts.TypeNode,
	visited: Set<string>,
): Set<StylingPropertyName> {
	if (ts.isTypeLiteralNode(typeNode)) {
		return stylingPropertiesForTypeMembers(typeNode.members);
	}
	if (ts.isTypeReferenceNode(typeNode) && ts.isIdentifier(typeNode.typeName)) {
		const name = typeNode.typeName.text;
		if (visited.has(name)) {
			return new Set(allStylingPropertyNames);
		}
		visited.add(name);
		const utilityResult = stylingPropertiesForUtilityType(
			sourceFile,
			name,
			typeNode.typeArguments,
			visited,
		);
		if (utilityResult !== null) return utilityResult;
		for (const statement of sourceFile.statements) {
			if (ts.isInterfaceDeclaration(statement) && statement.name.text === name) {
				const properties = stylingPropertiesForTypeMembers(statement.members);
				for (const heritageClause of statement.heritageClauses ?? []) {
					for (const heritageType of heritageClause.types) {
						if (ts.isIdentifier(heritageType.expression)) {
							for (const property of stylingPropertiesForUtilityType(
								sourceFile,
								heritageType.expression.text,
								heritageType.typeArguments,
								visited,
							) ?? allStylingPropertyNames) {
								properties.add(property);
							}
						}
					}
				}
				return properties;
			}
			if (ts.isTypeAliasDeclaration(statement) && statement.name.text === name) {
				return stylingPropertiesForTypeNode(sourceFile, statement.type, visited);
			}
		}
		return new Set(allStylingPropertyNames);
	}
	if (ts.isIntersectionTypeNode(typeNode) || ts.isUnionTypeNode(typeNode)) {
		const properties = new Set<StylingPropertyName>();
		for (const member of typeNode.types) {
			for (const property of stylingPropertiesForTypeNode(sourceFile, member, visited)) {
				properties.add(property);
			}
		}
		return properties;
	}
	return new Set(allStylingPropertyNames);
}

function stylingPropertiesForTypeMembers(
	members: ts.NodeArray<ts.TypeElement>,
): Set<StylingPropertyName> {
	const properties = new Set<StylingPropertyName>();
	for (const member of members) {
		if (!ts.isPropertySignature(member) || member.name === undefined) {
			return new Set(allStylingPropertyNames);
		}
		const name = propertyNameText(member.name);
		if (name === null) return new Set(allStylingPropertyNames);
		if (name === 'className' || name === 'style') properties.add(name);
	}
	return properties;
}

function stylingPropertiesForUtilityType(
	sourceFile: ts.SourceFile,
	name: string,
	typeArguments: ts.NodeArray<ts.TypeNode> | undefined,
	visited: Set<string>,
): Set<StylingPropertyName> | null {
	if (name !== 'Omit' && name !== 'Pick') return null;
	if (typeArguments?.length !== 2) return new Set(allStylingPropertyNames);
	const baseType = typeArguments.at(0);
	const propertyNamesType = typeArguments.at(1);
	if (baseType === undefined || propertyNamesType === undefined) {
		return new Set(allStylingPropertyNames);
	}
	const baseProperties = stylingPropertiesForTypeNode(sourceFile, baseType, visited);
	const namedProperties = stringLiteralTypeValues(propertyNamesType);
	if (namedProperties === null) return new Set(allStylingPropertyNames);
	if (name === 'Omit') {
		for (const property of namedProperties) baseProperties.delete(property as StylingPropertyName);
		return baseProperties;
	}
	return new Set([...baseProperties].filter((property) => namedProperties.has(property)));
}

function stringLiteralTypeValues(typeNode: ts.TypeNode): Set<string> | null {
	if (ts.isLiteralTypeNode(typeNode) && ts.isStringLiteral(typeNode.literal)) {
		return new Set([typeNode.literal.text]);
	}
	if (ts.isUnionTypeNode(typeNode)) {
		const values = new Set<string>();
		for (const member of typeNode.types) {
			const memberValues = stringLiteralTypeValues(member);
			if (memberValues === null) return null;
			for (const value of memberValues) values.add(value);
		}
		return values;
	}
	return null;
}

function findEnclosingParameter(
	identifier: ts.Identifier,
	name: string,
): ts.ParameterDeclaration | null {
	let ancestor: ts.Node | undefined = identifier.parent;
	while (ancestor !== undefined) {
		if (ts.isFunctionLike(ancestor)) {
			return (
				ancestor.parameters.find(
					(parameter) => ts.isIdentifier(parameter.name) && parameter.name.text === name,
				) ?? null
			);
		}
		ancestor = ancestor.parent;
	}
	return null;
}

function findVariableInitializer(sourceFile: ts.SourceFile, name: string): ts.Expression | null {
	for (const statement of sourceFile.statements) {
		if (!ts.isVariableStatement(statement)) continue;
		for (const declaration of statement.declarationList.declarations) {
			if (ts.isIdentifier(declaration.name) && declaration.name.text === name) {
				return declaration.initializer ?? null;
			}
		}
	}
	return null;
}

function findRestBinding(
	identifier: ts.Identifier,
	name: string,
): {
	readonly sourceExpression: ts.Expression;
	readonly excludedNames: ReadonlySet<string>;
} | null {
	let result: {
		readonly sourceExpression: ts.Expression;
		readonly excludedNames: ReadonlySet<string>;
	} | null = null;
	let searchRoot: ts.Node = identifier.getSourceFile();
	let ancestor: ts.Node | undefined = identifier.parent;
	while (ancestor !== undefined) {
		if (ts.isFunctionLike(ancestor)) {
			searchRoot = ancestor;
			break;
		}
		ancestor = ancestor.parent;
	}
	const visit = (node: ts.Node): void => {
		if (result !== null) return;
		if (
			ts.isVariableDeclaration(node) &&
			ts.isObjectBindingPattern(node.name) &&
			node.initializer !== undefined
		) {
			const restElement = node.name.elements.find(
				(element) =>
					element.dotDotDotToken !== undefined &&
					ts.isIdentifier(element.name) &&
					element.name.text === name,
			);
			if (restElement !== undefined) {
				result = {
					sourceExpression: node.initializer,
					excludedNames: new Set(
						node.name.elements.flatMap((element) => {
							if (element === restElement) return [];
							const propertyName = element.propertyName ?? element.name;
							return ts.isIdentifier(propertyName) || ts.isStringLiteralLike(propertyName)
								? [propertyName.text]
								: [];
						}),
					),
				};
			}
		}
		node.forEachChild(visit);
	};
	visit(searchRoot);
	return result;
}

function staticStringValue(expression: ts.Expression): string | null {
	const unwrapped = unwrapExpression(expression);
	return unwrapped !== null && ts.isStringLiteralLike(unwrapped) ? unwrapped.text : null;
}

function jsxAttributeExpression(
	initializer: ts.JsxAttributeValue | undefined,
): ts.Expression | null {
	if (initializer === undefined) return null;
	if (ts.isStringLiteral(initializer)) return initializer;
	return ts.isJsxExpression(initializer) ? (initializer.expression ?? null) : null;
}

function propertyNameText(name: ts.PropertyName): string | null {
	return ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)
		? name.text
		: null;
}

function unknownSpread(): JsxStylingSpreadResolution {
	return { classExpressions: [], styleExpressions: [], unknownStyling: true };
}

function mergeSpreadResolutions(
	results: readonly JsxStylingSpreadResolution[],
): JsxStylingSpreadResolution {
	return {
		classExpressions: results.flatMap(({ classExpressions }) => classExpressions),
		styleExpressions: results.flatMap(({ styleExpressions }) => styleExpressions),
		unknownStyling: results.some(({ unknownStyling }) => unknownStyling),
	};
}
