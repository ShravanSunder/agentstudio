import { type AtRule, type Declaration, type Node, parse, type Root, type Rule } from 'postcss';

import {
	isColorBearingCssProperty,
	paletteReferenceCount,
	rawColorOccurrenceCount,
} from './check-bridgeweb-style-system-literal-policy.ts';
import { type StyleSystemFinding } from './check-bridgeweb-style-system-model.ts';

export interface CssAnalysisResult {
	readonly findings: readonly StyleSystemFinding[];
	readonly primitiveEntries: ReadonlyMap<string, string>;
	readonly duplicatePrimitiveNames: readonly string[];
	readonly customClassStyleProperties: ReadonlyMap<string, ReadonlySet<string>>;
}

const bridgeAliasPattern = /--bridge-[\w-]+/gu;
const controlSelectorPattern =
	/(^|[\s>+~,])(?:button|input|select|textarea)(?=$|[\s>+~,.#[:])|\[role\s*=\s*['"]?(?:button|checkbox|menuitem|menuitemcheckbox|menuitemradio|option|radio|switch|tab)['"]?\]/iu;
const controlStylePropertyPattern =
	/^(?:background(?:-color)?|border(?:-.+)?|box-shadow|color|font(?:-.+)?|height|line-height|max-height|min-height|opacity|outline(?:-.+)?|padding(?:-.+)?|width)$/u;

export function analyzeCssSource(props: {
	readonly sourceText: string;
	readonly relativePath: string;
	readonly isCanonicalCss: boolean;
}): CssAnalysisResult {
	const root = parse(props.sourceText, { from: props.relativePath });
	const findings: StyleSystemFinding[] = [];
	const primitiveEntries = new Map<string, string>();
	const duplicatePrimitiveNames: string[] = [];
	const customClassStyleProperties = new Map<string, Set<string>>();
	const primitiveBounds = findPrimitiveBounds(props.sourceText);

	root.walkDecls((declaration: Declaration): void => {
		const offset = declaration.source?.start?.offset ?? 0;
		const inPrimitiveBlock =
			props.isCanonicalCss &&
			primitiveBounds !== null &&
			offset >= primitiveBounds.start &&
			offset <= primitiveBounds.end;

		if (inPrimitiveBlock && declaration.prop.startsWith('--palette-')) {
			if (primitiveEntries.has(declaration.prop)) {
				duplicatePrimitiveNames.push(declaration.prop);
			}
			primitiveEntries.set(declaration.prop, normalizeCssValue(declaration.value));
		}

		if (!inPrimitiveBlock) {
			const rawColorCount = rawColorOccurrenceCount(
				declaration.value,
				isColorBearingCssProperty(declaration.prop),
			);
			for (let occurrence = 0; occurrence < rawColorCount; occurrence += 1) {
				findings.push(
					findingForPostCssNode(
						'raw-color',
						props.relativePath,
						declaration,
						'Raw colors are allowed only in the canonical CSS primitive block or test fixtures.',
					),
				);
			}
		}

		if (!props.isCanonicalCss) {
			for (
				let occurrence = 0;
				occurrence < paletteReferenceCount(declaration.value);
				occurrence += 1
			) {
				findings.push(
					findingForPostCssNode(
						'palette-direct-read',
						props.relativePath,
						declaration,
						'Palette primitives may be read only by canonical CSS and the two static theme adapters.',
					),
				);
			}
		}

		addPatternFindings(
			findings,
			declaration,
			`${declaration.prop}: ${declaration.value}`,
			bridgeAliasPattern,
			{
				ruleId: 'bridge-alias',
				relativePath: props.relativePath,
				message: 'Transitional --bridge-* definitions and references are forbidden.',
			},
		);

		const parentRule = declaration.parent;
		if (
			parentRule?.type === 'rule' &&
			controlSelectorPattern.test((parentRule as Rule).selector) &&
			declaration.prop === 'font' &&
			!hasLayerBaseAncestor(declaration)
		) {
			findings.push(
				findingForPostCssNode(
					'unlayered-control-reset',
					props.relativePath,
					declaration,
					'Control font resets must be inside @layer base so primitive typography can win.',
				),
			);
		}

		const isAllowedCanonicalBaseReset =
			props.isCanonicalCss && hasLayerBaseAncestor(declaration) && declaration.prop === 'font';
		if (
			!isPrimitiveSourcePath(props.relativePath) &&
			!isAllowedCanonicalBaseReset &&
			parentRule?.type === 'rule' &&
			controlSelectorPattern.test((parentRule as Rule).selector) &&
			controlStylePropertyPattern.test(declaration.prop)
		) {
			findings.push(
				findingForPostCssNode(
					'control-style-override',
					props.relativePath,
					declaration,
					`Control declaration "${declaration.prop}" belongs to an owned UI primitive.`,
				),
			);
		}

		if (parentRule?.type === 'rule') {
			for (const className of cssClassNames((parentRule as Rule).selector)) {
				const styleProperties = customClassStyleProperties.get(className) ?? new Set<string>();
				styleProperties.add(declaration.prop);
				customClassStyleProperties.set(className, styleProperties);
			}
		}
	});

	root.walkRules((rule: Rule): void => {
		if (/(^|[^\w-])\.dark(?![\w-])/u.test(rule.selector)) {
			findings.push(
				findingForPostCssNode(
					'appearance-conditional',
					props.relativePath,
					rule,
					'BridgeWeb is dark-only; .dark selector branches are forbidden.',
				),
			);
		}
	});

	root.walkAtRules((atRule: AtRule): void => {
		if (atRule.name.toLowerCase() === 'media' && /prefers-color-scheme/iu.test(atRule.params)) {
			findings.push(
				findingForPostCssNode(
					'appearance-conditional',
					props.relativePath,
					atRule,
					'BridgeWeb is dark-only; prefers-color-scheme branches are forbidden.',
				),
			);
		}
	});

	return { findings, primitiveEntries, duplicatePrimitiveNames, customClassStyleProperties };
}

function cssClassNames(selector: string): readonly string[] {
	return [...selector.matchAll(/\.([_a-zA-Z][\w-]*)/gu)].map((match) => match[1] ?? '');
}

function findPrimitiveBounds(
	sourceText: string,
): { readonly start: number; readonly end: number } | null {
	const startMarker = '/* @design-primitives:start */';
	const endMarker = '/* @design-primitives:end */';
	const start = sourceText.indexOf(startMarker);
	const end = sourceText.indexOf(endMarker);
	return start >= 0 && end > start ? { start: start + startMarker.length, end } : null;
}

function normalizeCssValue(value: string): string {
	return value.trim().replace(/\s+/gu, ' ').toLowerCase();
}

function hasLayerBaseAncestor(declaration: Declaration): boolean {
	let ancestor: Node | undefined = declaration.parent;
	while (ancestor !== undefined) {
		const ancestorName = 'name' in ancestor ? ancestor.name : null;
		const ancestorParameters = 'params' in ancestor ? ancestor.params : null;
		if (
			ancestor.type === 'atrule' &&
			ancestorName === 'layer' &&
			typeof ancestorParameters === 'string' &&
			ancestorParameters.trim() === 'base'
		) {
			return true;
		}
		ancestor = ancestor.parent;
	}
	return false;
}

function isPrimitiveSourcePath(relativePath: string): boolean {
	return relativePath.startsWith('src/components/ui/');
}

function addPatternFindings(
	findings: StyleSystemFinding[],
	declaration: Declaration,
	text: string,
	pattern: RegExp,
	base: Pick<StyleSystemFinding, 'ruleId' | 'relativePath' | 'message'>,
): void {
	pattern.lastIndex = 0;
	while (pattern.exec(text) !== null) {
		findings.push(findingForPostCssNode(base.ruleId, base.relativePath, declaration, base.message));
	}
}

function findingForPostCssNode(
	ruleId: StyleSystemFinding['ruleId'],
	relativePath: string,
	node: Declaration | Rule | AtRule | Root,
	message: string,
): StyleSystemFinding {
	return {
		ruleId,
		relativePath,
		line: node.source?.start?.line ?? 1,
		column: node.source?.start?.column ?? 1,
		message,
	};
}
