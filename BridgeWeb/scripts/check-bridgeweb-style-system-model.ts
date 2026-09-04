import type { Node } from 'typescript';

export type StyleSystemRuleId =
	| 'appearance-conditional'
	| 'bridge-alias'
	| 'control-style-override'
	| 'evaluation-failure'
	| 'palette-direct-read'
	| 'palette-parity'
	| 'raw-color'
	| 'unlayered-control-reset'
	| 'unknown-control-classes';

export interface StyleSystemFinding {
	readonly ruleId: StyleSystemRuleId;
	readonly relativePath: string;
	readonly line: number;
	readonly column: number;
	readonly message: string;
}

export interface StyleSystemReport {
	readonly ok: boolean;
	readonly findings: readonly StyleSystemFinding[];
}

export interface SourceLocationOwner {
	readonly getLineAndCharacterOfPosition: (position: number) => {
		readonly line: number;
		readonly character: number;
	};
}

export function findingAtPosition(props: {
	readonly ruleId: StyleSystemRuleId;
	readonly relativePath: string;
	readonly sourceFile: SourceLocationOwner;
	readonly position: number;
	readonly message: string;
}): StyleSystemFinding {
	const location = props.sourceFile.getLineAndCharacterOfPosition(props.position);
	return {
		ruleId: props.ruleId,
		relativePath: props.relativePath,
		line: location.line + 1,
		column: location.character + 1,
		message: props.message,
	};
}

export function findingAtNode(props: {
	readonly ruleId: StyleSystemRuleId;
	readonly relativePath: string;
	readonly node: Node;
	readonly message: string;
}): StyleSystemFinding {
	return findingAtPosition({
		...props,
		sourceFile: props.node.getSourceFile(),
		position: props.node.getStart(),
	});
}

export function compareStyleSystemFindings(
	left: StyleSystemFinding,
	right: StyleSystemFinding,
): number {
	return (
		left.relativePath.localeCompare(right.relativePath) ||
		left.line - right.line ||
		left.column - right.column ||
		left.ruleId.localeCompare(right.ruleId) ||
		left.message.localeCompare(right.message)
	);
}

export function evaluationFailure(relativePath: string, message: string): StyleSystemFinding {
	return {
		ruleId: 'evaluation-failure',
		relativePath,
		line: 1,
		column: 1,
		message,
	};
}
