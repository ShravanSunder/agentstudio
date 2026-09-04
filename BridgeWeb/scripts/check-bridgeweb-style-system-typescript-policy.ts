import ts from 'typescript';

import { isRawPaletteUtility } from './check-bridgeweb-style-system-classification.ts';
import { analyzeCssSource } from './check-bridgeweb-style-system-css.ts';
import {
	paletteReferenceCount,
	rawColorOccurrenceCount,
} from './check-bridgeweb-style-system-literal-policy.ts';
import { findingAtNode, type StyleSystemFinding } from './check-bridgeweb-style-system-model.ts';
import { classifyJsxRole } from './check-bridgeweb-style-system-typescript-jsx-resolution.ts';
import {
	resolveStaticClasses,
	resolveStaticTextFragments,
	splitClassTokens,
	unwrapExpression,
} from './check-bridgeweb-style-system-typescript-resolution.ts';
import type { TypeScriptSourceRecord } from './check-bridgeweb-style-system-typescript.ts';

const bridgeAliasPattern = /--bridge-[\w-]+/gu;
const paletteMirrorModulePattern =
	/(?:^|\/)design-tokens\/bridge-design-palette(?:\.[cm]?[jt]s|\.js)?$/u;
const paletteConsumerPaths = new Set([
	'src/app/bridge-viewer-tree-theme.ts',
	'src/review-viewer/code-view/bridge-code-view-theme.ts',
]);

export function checkTypeScriptPolicyNode(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	node: ts.Node,
	findings: StyleSystemFinding[],
): void {
	checkLiteralPolicies(record, node, findings);
	checkUnsafeCssPolicy(records, record, node, findings);
	checkPaletteAccessPolicy(record, node, findings);
}

export function checkJsxPolicy(props: {
	readonly records: ReadonlyMap<string, TypeScriptSourceRecord>;
	readonly record: TypeScriptSourceRecord;
	readonly element: ts.JsxOpeningLikeElement;
	readonly findings: StyleSystemFinding[];
}): void {
	checkDynamicRole(props.record, props.element, props.findings);
	checkAppearanceClasses(props.records, props.record, props.element, props.findings);
	checkInlineStyleLiteralColors(props.record, props.element, props.findings);
}

export function checkInlineStyleExpressionColors(
	record: TypeScriptSourceRecord,
	expression: ts.Expression,
	findingNode: ts.Node,
	findings: StyleSystemFinding[],
): void {
	const unwrapped = unwrapExpression(expression);
	if (unwrapped === null || !ts.isObjectLiteralExpression(unwrapped)) return;
	for (const property of unwrapped.properties) {
		if (!ts.isPropertyAssignment(property)) continue;
		const value = unwrapExpression(property.initializer);
		if (value === null || !ts.isStringLiteralLike(value)) continue;
		for (
			let occurrence = 0;
			occurrence < rawColorOccurrenceCount(value.text, true);
			occurrence += 1
		) {
			findings.push(
				findingAtNode({
					ruleId: 'raw-color',
					relativePath: record.relativePath,
					node: findingNode,
					message: 'Inline style colors must use canonical semantic roles.',
				}),
			);
		}
	}
}

function checkLiteralPolicies(
	record: TypeScriptSourceRecord,
	node: ts.Node,
	findings: StyleSystemFinding[],
): void {
	if (!ts.isStringLiteralLike(node) && !ts.isTemplateExpression(node)) return;
	const fragments = ts.isTemplateExpression(node)
		? [node.head.text, ...node.templateSpans.map((span) => span.literal.text)]
		: [node.text];
	for (const fragment of fragments) {
		if (!isPaletteMirrorPath(record.relativePath)) {
			for (
				let occurrence = 0;
				occurrence < rawColorOccurrenceCount(fragment, false);
				occurrence += 1
			) {
				findings.push(
					findingAtNode({
						ruleId: 'raw-color',
						relativePath: record.relativePath,
						node,
						message:
							'Raw colors are allowed only in the canonical CSS primitive block or palette mirror.',
					}),
				);
			}
		}
		bridgeAliasPattern.lastIndex = 0;
		while (bridgeAliasPattern.exec(fragment) !== null) {
			findings.push(
				findingAtNode({
					ruleId: 'bridge-alias',
					relativePath: record.relativePath,
					node,
					message: 'Transitional --bridge-* definitions and references are forbidden.',
				}),
			);
		}
	}
}

function checkUnsafeCssPolicy(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	node: ts.Node,
	findings: StyleSystemFinding[],
): void {
	if (!ts.isPropertyAssignment(node) || propertyNameText(node.name) !== 'unsafeCSS') return;
	const result = resolveStaticTextFragments(records, record, node.initializer, new Set());
	if (result.unknown) {
		findings.push(
			findingAtNode({
				ruleId: 'evaluation-failure',
				relativePath: record.relativePath,
				node,
				message: 'Cannot statically evaluate consumed unsafeCSS.',
			}),
		);
		return;
	}
	try {
		const embeddedFindings = analyzeCssSource({
			sourceText: result.fragments.join(''),
			relativePath: record.relativePath,
			isCanonicalCss: false,
		}).findings;
		const sourceFinding = findingAtNode({
			ruleId: 'evaluation-failure',
			relativePath: record.relativePath,
			node,
			message: '',
		});
		findings.push(
			...embeddedFindings.map((embeddedFinding) => ({
				...embeddedFinding,
				line: sourceFinding.line,
				column: sourceFinding.column,
				message: `${embeddedFinding.message} (embedded CSS ${embeddedFinding.line}:${embeddedFinding.column})`,
			})),
		);
	} catch (error: unknown) {
		findings.push(
			findingAtNode({
				ruleId: 'evaluation-failure',
				relativePath: record.relativePath,
				node,
				message: `Cannot parse consumed unsafeCSS: ${error instanceof Error ? error.message : String(error)}`,
			}),
		);
	}
}

function checkAppearanceClasses(
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	findings: StyleSystemFinding[],
): void {
	const classAttribute = element.attributes.properties.find(
		(attribute): attribute is ts.JsxAttribute =>
			ts.isJsxAttribute(attribute) && attribute.name.getText() === 'className',
	);
	if (classAttribute?.initializer === undefined) return;
	const expression = jsxAttributeExpression(classAttribute.initializer);
	if (expression === null) return;
	const result = resolveStaticClasses(records, record, expression, new Set());
	for (const classToken of result.classTokens.filter(hasDarkVariant)) {
		findings.push(
			findingAtNode({
				ruleId: 'appearance-conditional',
				relativePath: record.relativePath,
				node: classAttribute,
				message: `BridgeWeb is dark-only; appearance class "${classToken}" is forbidden.`,
			}),
		);
	}
	for (const classToken of result.classTokens.filter(isRawPaletteUtility)) {
		findings.push(
			findingAtNode({
				ruleId: 'raw-color',
				relativePath: record.relativePath,
				node: classAttribute,
				message: `Raw palette utility "${classToken}" must use a canonical semantic role.`,
			}),
		);
	}
}

function checkDynamicRole(
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	findings: StyleSystemFinding[],
): void {
	if (classifyJsxRole(element) !== 'unknown') return;
	const roleAttribute = element.attributes.properties.find(
		(attribute): attribute is ts.JsxAttribute =>
			ts.isJsxAttribute(attribute) && attribute.name.getText() === 'role',
	);
	if (roleAttribute === undefined) return;
	findings.push(
		findingAtNode({
			ruleId: 'unknown-control-classes',
			relativePath: record.relativePath,
			node: roleAttribute,
			message:
				'Cannot statically classify a dynamic JSX role; role-based controls must fail closed.',
		}),
	);
}

function checkInlineStyleLiteralColors(
	record: TypeScriptSourceRecord,
	element: ts.JsxOpeningLikeElement,
	findings: StyleSystemFinding[],
): void {
	const styleAttribute = element.attributes.properties.find(
		(attribute): attribute is ts.JsxAttribute =>
			ts.isJsxAttribute(attribute) && attribute.name.getText() === 'style',
	);
	if (styleAttribute?.initializer === undefined) return;
	const expression = jsxAttributeExpression(styleAttribute.initializer);
	if (expression !== null) {
		checkInlineStyleExpressionColors(record, expression, styleAttribute, findings);
	}
}

function checkPaletteAccessPolicy(
	record: TypeScriptSourceRecord,
	node: ts.Node,
	findings: StyleSystemFinding[],
): void {
	if (isPaletteAccessPath(record.relativePath)) return;
	if (
		ts.isImportDeclaration(node) &&
		ts.isStringLiteral(node.moduleSpecifier) &&
		paletteMirrorModulePattern.test(node.moduleSpecifier.text)
	) {
		findings.push(
			findingAtNode({
				ruleId: 'palette-direct-read',
				relativePath: record.relativePath,
				node,
				message:
					'The static palette mirror may be imported only by the two renderer theme adapters.',
			}),
		);
	}
	if (
		(ts.isElementAccessExpression(node) || ts.isPropertyAccessExpression(node)) &&
		ts.isIdentifier(node.expression) &&
		node.expression.text === 'bridgeDesignPalette'
	) {
		findings.push(
			findingAtNode({
				ruleId: 'palette-direct-read',
				relativePath: record.relativePath,
				node,
				message: 'Palette primitives may be read only by the two renderer theme adapters.',
			}),
		);
	}
	if (ts.isStringLiteralLike(node)) {
		for (let occurrence = 0; occurrence < paletteReferenceCount(node.text); occurrence += 1) {
			findings.push(
				findingAtNode({
					ruleId: 'palette-direct-read',
					relativePath: record.relativePath,
					node,
					message: 'Palette CSS variables may be read only by canonical CSS.',
				}),
			);
		}
	}
}

function jsxAttributeExpression(initializer: ts.JsxAttributeValue): ts.Expression | null {
	if (ts.isStringLiteral(initializer)) return initializer;
	return ts.isJsxExpression(initializer) ? (initializer.expression ?? null) : null;
}

function hasDarkVariant(value: string): boolean {
	return splitClassTokens(value).some((token) => token.split(':').includes('dark'));
}

function propertyNameText(name: ts.PropertyName): string | null {
	return ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)
		? name.text
		: null;
}

function isPaletteMirrorPath(relativePath: string): boolean {
	return relativePath === 'src/design-tokens/bridge-design-palette.ts';
}

function isPaletteAccessPath(relativePath: string): boolean {
	return isPaletteMirrorPath(relativePath) || paletteConsumerPaths.has(relativePath);
}
