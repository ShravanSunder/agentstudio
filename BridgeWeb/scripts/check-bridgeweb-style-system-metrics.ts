import { parse } from 'postcss';
import ts from 'typescript';

import type { StyleSystemFinding } from './check-bridgeweb-style-system-model.ts';
import { unwrapExpression } from './check-bridgeweb-style-system-typescript-resolution.ts';
import type { TypeScriptSourceRecord } from './check-bridgeweb-style-system-typescript.ts';

/** The same canonical/mirror gate covers lengths consumed by virtual layout. */
export function rowMetricParityFindings(props: {
	readonly cssSource: string;
	readonly mirror: TypeScriptSourceRecord | undefined;
}): readonly StyleSystemFinding[] {
	const cssEntries = new Map<string, string>();
	const mirrorEntries = new Map<string, number>();
	const problems: string[] = [];
	let hasMirror = false;
	parse(props.cssSource).walkDecls(/^--row-height-/u, (declaration): void => {
		if (cssEntries.has(declaration.prop)) problems.push(`Duplicate metric ${declaration.prop}.`);
		if (declaration.parent?.type !== 'rule' || declaration.parent.selector !== ':root') {
			problems.push(`Metric ${declaration.prop} must be canonical at :root.`);
		}
		cssEntries.set(declaration.prop, declaration.value.trim());
	});
	for (const statement of props.mirror?.sourceFile.statements ?? []) {
		if (!ts.isVariableStatement(statement)) continue;
		for (const declaration of statement.declarationList.declarations) {
			if (!ts.isIdentifier(declaration.name) || declaration.name.text !== 'bridgeDesignRowMetrics')
				continue;
			hasMirror = true;
			const initializer = unwrapExpression(declaration.initializer);
			if (initializer === null || !ts.isObjectLiteralExpression(initializer)) {
				problems.push('bridgeDesignRowMetrics must be a static numeric object.');
				continue;
			}
			for (const property of initializer.properties) {
				if (!ts.isPropertyAssignment(property)) {
					problems.push('Row metrics may contain only literal property assignments.');
					continue;
				}
				const name =
					ts.isIdentifier(property.name) || ts.isStringLiteral(property.name)
						? property.name.text
						: null;
				const value = unwrapExpression(property.initializer);
				if (name === null || value === null || !ts.isNumericLiteral(value)) {
					problems.push('Row metrics require literal keys and numeric lengths.');
					continue;
				}
				const key = `--row-height-${name}`;
				if (mirrorEntries.has(key)) problems.push(`Duplicate metric ${key}.`);
				mirrorEntries.set(key, Number(value.text));
			}
		}
	}
	// Minimal checker fixtures without row recipes have no metric contract to mirror.
	if (cssEntries.size === 0 && !hasMirror) return [];
	const keys = new Set([
		'--row-height-default',
		'--row-height-descriptive',
		...cssEntries.keys(),
		...mirrorEntries.keys(),
	]);
	for (const key of keys) {
		const css = cssEntries.get(key);
		const mirrored = mirrorEntries.get(key);
		if (css === undefined || mirrored === undefined || mirrored <= 0 || css !== `${mirrored}px`) {
			problems.push(
				`Metric ${key} differs or is missing: CSS=${css ?? 'missing'}; mirror=${mirrored ?? 'missing'}.`,
			);
		}
	}
	return problems.map(
		(message): StyleSystemFinding => ({
			ruleId: 'metric-parity',
			relativePath: 'src/design-tokens/bridge-design-row-metrics.ts',
			line: 1,
			column: 1,
			message,
		}),
	);
}
