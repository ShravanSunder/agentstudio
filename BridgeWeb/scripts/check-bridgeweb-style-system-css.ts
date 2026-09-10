import {
	type AtRule,
	type Declaration,
	list,
	type Node,
	parse,
	type Root,
	type Rule,
} from 'postcss';

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
	readonly customClassDescendantStyleProperties: ReadonlyMap<string, ReadonlySet<string>>;
}

const bridgeAliasPattern = /--bridge-[\w-]+/gu;
const controlSelectorPattern =
	/(^|[\s>+~,])(?:button|input|select|textarea)(?=$|[\s>+~,.#[:])|\[role\s*=\s*['"]?(?:button|checkbox|menuitem|menuitemcheckbox|menuitemradio|option|radio|switch|tab)['"]?\]/iu;
const controlStylePropertyPattern =
	/^(?:background(?:-color)?|border(?:-.+)?|box-shadow|color|font(?:-.+)?|height|line-height|max-height|min-height|opacity|outline(?:-.+)?|padding(?:-.+)?|width)$/u;

const ownedContentSelectorPattern =
	/\[data-slot\s*=\s*['"]?(?:item-(?:content|label|description|metadata)|combobox-item(?:-description)?|dropdown-menu-(?:item(?:-description)?|label|description|header)|status-badge|input-group(?:-addon|-control)?|field-(?:label|description|error)|alert-(?:title|description|action))['"]?\]/iu;

function targetsOwnedRecipe(selector: string): boolean {
	return controlSelectorPattern.test(selector) || ownedContentSelectorPattern.test(selector);
}

export function analyzeCssSource(props: {
	readonly sourceText: string;
	readonly relativePath: string;
	readonly isCanonicalCss: boolean;
	readonly context?: 'document' | 'renderer-shadow';
}): CssAnalysisResult {
	const root = parse(props.sourceText, { from: props.relativePath });
	const findings: StyleSystemFinding[] = [];
	const primitiveEntries = new Map<string, string>();
	const duplicatePrimitiveNames: string[] = [];
	const customClassStyleProperties = new Map<string, Set<string>>();
	const customClassDescendantStyleProperties = new Map<string, Set<string>>();
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
			targetsOwnedRecipe((parentRule as Rule).selector) &&
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
			parentRule?.type === 'rule' &&
			!isKeyframeDeclaration(declaration) &&
			(parentRule as Rule).selectors.some(
				(selector) =>
					!targetsOwnedRecipe(selector) &&
					!selectorHasClassAnchor(selector) &&
					!(props.context === 'renderer-shadow' && isRendererInternalSelector(selector)) &&
					!(props.isCanonicalCss && [':root', '#root', 'html', 'body'].includes(selector)),
			) &&
			controlStylePropertyPattern.test(declaration.prop)
		) {
			findings.push(
				findingForPostCssNode(
					'control-style-override',
					props.relativePath,
					declaration,
					`Cannot prove selector destination for declaration "${declaration.prop}"; anchor semantic content with a class or use an owned content slot.`,
				),
			);
		}
		if (
			!isPrimitiveSourcePath(props.relativePath) &&
			!isAllowedCanonicalBaseReset &&
			parentRule?.type === 'rule' &&
			targetsOwnedRecipe((parentRule as Rule).selector) &&
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
			const selector = (parentRule as Rule).selector;
			for (const className of cssClassNames(selector)) {
				const styleProperties = customClassStyleProperties.get(className) ?? new Set<string>();
				styleProperties.add(declaration.prop);
				customClassStyleProperties.set(className, styleProperties);
				if (classOwnsDescendantSelector(selector, className)) {
					const descendantProperties =
						customClassDescendantStyleProperties.get(className) ?? new Set<string>();
					descendantProperties.add(declaration.prop);
					customClassDescendantStyleProperties.set(className, descendantProperties);
				}
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

	return {
		findings,
		primitiveEntries,
		duplicatePrimitiveNames,
		customClassStyleProperties,
		customClassDescendantStyleProperties,
	};
}

function cssClassNames(selector: string): readonly string[] {
	return [...selector.matchAll(/\.([_a-zA-Z][\w-]*)/gu)].map((match) => match[1] ?? '');
}

function classOwnsDescendantSelector(selector: string, className: string): boolean {
	const escapedClassName = className.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
	const classPattern = new RegExp(`\\.${escapedClassName}(?![\\w-])`, 'gu');
	return list.comma(selector).some((selectorBranch) => {
		for (const match of selectorBranch.matchAll(classPattern)) {
			const suffix = selectorBranch.slice((match.index ?? 0) + match[0].length);
			if (/(?:\s|[>+~])+[^\s>+~]/u.test(suffix)) return true;
		}
		return false;
	});
}

function selectorHasClassAnchor(selector: string): boolean {
	// A class in an attribute value or :is() alternative is not a proven anchor.
	// More complex selector forms remain unsupported rather than inferred safe.
	return /^(?:[a-z][\w-]*)?\.[_a-zA-Z][\w-]*/iu.test(selector);
}

function isRendererInternalSelector(selector: string): boolean {
	// Pierre injects unsafeCSS into its shadow root. Its data attributes name
	// renderer internals; slotted React content and owned slots are not that scope.
	return (
		/^(?:\[data-[\w-]+|:host(?:\b|\())/u.test(selector) &&
		!/(?:::slotted|\[data-slot)/u.test(selector)
	);
}

function isKeyframeDeclaration(declaration: Declaration): boolean {
	let ancestor: Node | undefined = declaration.parent;
	while (ancestor !== undefined) {
		if (ancestor.type === 'atrule' && (ancestor as AtRule).name.endsWith('keyframes')) return true;
		ancestor = ancestor.parent;
	}
	return false;
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
