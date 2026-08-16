import type { Dirent } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { bridgeDesignPalette } from '../src/design-tokens/bridge-design-palette.ts';
import { appearanceBranchAllowlist } from './design-token-allowlists/appearance-branches.ts';
import { bridgeTokenAllowlist } from './design-token-allowlists/bridge-tokens.ts';
import { controlGeometryAllowlist } from './design-token-allowlists/control-geometry.ts';
import { rawColorLiteralAllowlist } from './design-token-allowlists/raw-color-literals.ts';

type DesignTokenRuleId =
	| 'no-raw-color-literal'
	| 'no-bridge-token'
	| 'no-bespoke-control-geometry'
	| 'palette-mirror'
	| 'no-appearance-branch';

interface DesignTokenFinding {
	readonly relativePath: string;
	readonly line: number;
	readonly column: number;
	readonly ruleId: DesignTokenRuleId;
	readonly message: string;
}

interface SourceFileRecord {
	readonly absolutePath: string;
	readonly relativePath: string;
	readonly sourceText: string;
}

interface CountAllowlist {
	readonly [relativePath: string]: number;
}

interface IndexedMatch {
	readonly index: number;
	readonly text: string;
}

const packageRootPath = fileURLToPath(new URL('../', import.meta.url));
const sourceRootPath = join(packageRootPath, 'src');
const checkedExtensions = new Set(['.css', '.ts', '.tsx']);
const ignoredDirectoryNames = new Set(['node_modules', 'dist', 'coverage', '.vite']);
const primitiveStartMarker = '/* @design-primitives:start */';
const primitiveEndMarker = '/* @design-primitives:end */';
const rawColorPattern = /#[0-9a-f]{3,8}\b|\b(?:rgb|rgba|hsl|hsla|oklch)\([^\n;]+\)/giu;
const bridgeTokenPattern = /--bridge-[a-z0-9_-]+/giu;
const cssControlGeometryPattern = /\b(?:font-size|height)\s*:\s*\d+(?:\.\d+)?px\b/giu;
const arbitraryControlUtilityPattern = /\b(?:text|h|size|min-h)-\[\d+(?:\.\d+)?px\]/giu;
const nativeControlElementPattern = /<(?:button|input|textarea)\b[\s\S]*?>/giu;
const bareControlUtilityPattern = /\b(?:h|text)-\d+(?:\.\d+)?\b/giu;
const appearanceVariantPattern = /dark:/gu;
const appearanceMediaPattern = /prefers-color-scheme/giu;
const allowedBridgeAliasNames: ReadonlySet<string> = new Set([
	'--bridge-app-bg',
	'--bridge-canvas-bg',
	'--bridge-header-bg',
	'--bridge-header-control-bg',
	'--bridge-header-control-active-bg',
	'--bridge-surface-bg',
	'--bridge-surface-raised-bg',
	'--bridge-menu-bg',
	'--bridge-surface-muted-bg',
	'--bridge-border-subtle',
	'--bridge-border-opaque',
	'--bridge-text-primary',
	'--bridge-text-secondary',
	'--bridge-text-muted',
	'--bridge-accent',
	'--bridge-accent-soft',
	'--bridge-focus-border',
	'--bridge-focus-ring',
	'--bridge-focus-dot-shadow',
	'--bridge-menu-border',
	'--bridge-menu-ring',
	'--bridge-divider-shadow',
	'--bridge-floating-panel-shadow',
	'--bridge-menu-shadow',
	'--bridge-tree-sticky-shadow',
	'--bridge-scrollbar-size',
	'--bridge-scrollbar-thumb',
	'--bridge-scrollbar-thumb-hover',
	'--bridge-scrollbar-track',
	'--bridge-motion-fast',
	'--bridge-list-hover-bg',
	'--bridge-list-selected-bg',
	'--bridge-added',
	'--bridge-deleted',
	'--bridge-warning',
	'--bridge-code-view-file-separator',
]);

async function checkBridgeWebDesignTokens(): Promise<readonly DesignTokenFinding[]> {
	const sourceFiles = await collectSourceFiles(sourceRootPath);
	const rawColorFindings = sourceFiles.flatMap(findRawColorLiterals);
	const bridgeTokenFindings = sourceFiles.flatMap(findBridgeTokens);
	const geometryFindings = sourceFiles.flatMap(findBespokeControlGeometry);
	const appearanceFindings = sourceFiles.flatMap(findAppearanceBranches);
	const paletteFindings = await checkPaletteMirror(sourceFiles);

	return [
		...applyCountAllowlist(rawColorFindings, rawColorLiteralAllowlist, 'no-raw-color-literal'),
		...applyCountAllowlist(bridgeTokenFindings, bridgeTokenAllowlist, 'no-bridge-token'),
		...applyCountAllowlist(
			geometryFindings,
			controlGeometryAllowlist,
			'no-bespoke-control-geometry',
		),
		...paletteFindings,
		...applyCountAllowlist(appearanceFindings, appearanceBranchAllowlist, 'no-appearance-branch'),
	].toSorted(compareFindings);
}

async function collectSourceFiles(directoryPath: string): Promise<readonly SourceFileRecord[]> {
	const entries = await readdir(directoryPath, { withFileTypes: true });
	const records = await Promise.all(
		entries.map(async (entry: Dirent): Promise<readonly SourceFileRecord[]> => {
			const absolutePath = join(directoryPath, entry.name);

			if (entry.isDirectory()) {
				return ignoredDirectoryNames.has(entry.name) ? [] : collectSourceFiles(absolutePath);
			}
			if (!entry.isFile() || !checkedExtensions.has(extname(entry.name))) {
				return [];
			}

			return [
				{
					absolutePath,
					relativePath: normalizePath(relative(packageRootPath, absolutePath)),
					sourceText: await readFile(absolutePath, 'utf8'),
				},
			];
		}),
	);

	return records.flat();
}

function findRawColorLiterals(sourceFile: SourceFileRecord): readonly DesignTokenFinding[] {
	if (isRawColorExemptPath(sourceFile.relativePath)) {
		return [];
	}

	let sourceText = sourceFile.sourceText;
	const sourceOffset = 0;
	if (sourceFile.relativePath === 'src/app/bridge-app.css') {
		const primitiveRange = readPrimitiveRange(sourceText);
		sourceText = `${sourceText.slice(0, primitiveRange.start)}${' '.repeat(
			primitiveRange.end - primitiveRange.start,
		)}${sourceText.slice(primitiveRange.end)}`;
	}
	if (sourceFile.relativePath.endsWith('.css')) {
		sourceText = maskCssComments(sourceText);
	}

	return matchAll(sourceText, rawColorPattern).map(
		(match: IndexedMatch): DesignTokenFinding =>
			findingAt(sourceFile, sourceOffset + match.index, 'no-raw-color-literal', match.text),
	);
}

function maskCssComments(sourceText: string): string {
	return sourceText.replaceAll(/\/\*[\s\S]*?\*\//gu, (comment: string): string =>
		comment.replaceAll(/[^\n]/gu, ' '),
	);
}

function findBridgeTokens(sourceFile: SourceFileRecord): readonly DesignTokenFinding[] {
	return matchAll(sourceFile.sourceText, bridgeTokenPattern)
		.filter((match: IndexedMatch): boolean => !isAllowedBridgeAliasDefinition(sourceFile, match))
		.map(
			(match: IndexedMatch): DesignTokenFinding =>
				findingAt(sourceFile, match.index, 'no-bridge-token', match.text),
		);
}

function findBespokeControlGeometry(sourceFile: SourceFileRecord): readonly DesignTokenFinding[] {
	if (sourceFile.relativePath.startsWith('src/components/ui/')) {
		return [];
	}

	const findings: DesignTokenFinding[] = [];
	if (sourceFile.relativePath.endsWith('.css') || sourceFile.sourceText.includes('`')) {
		for (const match of matchAll(sourceFile.sourceText, cssControlGeometryPattern)) {
			findings.push(findingAt(sourceFile, match.index, 'no-bespoke-control-geometry', match.text));
		}
	}

	if (!sourceFile.relativePath.endsWith('.tsx')) {
		return findings;
	}

	for (const match of matchAll(sourceFile.sourceText, arbitraryControlUtilityPattern)) {
		findings.push(findingAt(sourceFile, match.index, 'no-bespoke-control-geometry', match.text));
	}

	for (const elementMatch of matchAll(sourceFile.sourceText, nativeControlElementPattern)) {
		for (const utilityMatch of matchAll(elementMatch.text, bareControlUtilityPattern)) {
			findings.push(
				findingAt(
					sourceFile,
					elementMatch.index + utilityMatch.index,
					'no-bespoke-control-geometry',
					utilityMatch.text,
				),
			);
		}
	}

	return findings;
}

function findAppearanceBranches(sourceFile: SourceFileRecord): readonly DesignTokenFinding[] {
	return [
		...matchAll(sourceFile.sourceText, appearanceVariantPattern),
		...matchAll(sourceFile.sourceText, appearanceMediaPattern),
	].map(
		(match: IndexedMatch): DesignTokenFinding =>
			findingAt(sourceFile, match.index, 'no-appearance-branch', match.text),
	);
}

async function checkPaletteMirror(
	sourceFiles: readonly SourceFileRecord[],
): Promise<readonly DesignTokenFinding[]> {
	const cssFile = sourceFiles.find(
		(sourceFile: SourceFileRecord): boolean => sourceFile.relativePath === 'src/app/bridge-app.css',
	);
	if (cssFile === undefined) {
		throw new Error('Missing canonical src/app/bridge-app.css');
	}

	const primitiveRange = readPrimitiveRange(cssFile.sourceText);
	const primitiveText = cssFile.sourceText.slice(primitiveRange.start, primitiveRange.end);
	const cssPrimitiveValues = new Map<string, { readonly value: string; readonly index: number }>();
	const declarationPattern = /(--palette-[a-z0-9_-]+)\s*:\s*([^;]+);/giu;
	for (const match of primitiveText.matchAll(declarationPattern)) {
		const tokenName = match[1];
		const tokenValue = match[2];
		if (tokenName === undefined || tokenValue === undefined || match.index === undefined) {
			throw new Error('Malformed design primitive declaration');
		}
		cssPrimitiveValues.set(tokenName, {
			value: tokenValue.trim(),
			index: primitiveRange.start + match.index,
		});
	}

	const findings: DesignTokenFinding[] = [];
	for (const [tokenName, mirrorValue] of Object.entries(bridgeDesignPalette)) {
		const cssValue = cssPrimitiveValues.get(tokenName);
		if (cssValue === undefined) {
			findings.push(
				findingAt(cssFile, primitiveRange.start, 'palette-mirror', `missing CSS ${tokenName}`),
			);
			continue;
		}
		if (normalizePrimitiveValue(cssValue.value) !== normalizePrimitiveValue(mirrorValue)) {
			findings.push(
				findingAt(
					cssFile,
					cssValue.index,
					'palette-mirror',
					`${tokenName} differs from the TypeScript mirror`,
				),
			);
		}
		cssPrimitiveValues.delete(tokenName);
	}

	for (const [tokenName, cssValue] of cssPrimitiveValues) {
		findings.push(
			findingAt(cssFile, cssValue.index, 'palette-mirror', `missing mirror ${tokenName}`),
		);
	}

	return findings;
}

function readPrimitiveRange(sourceText: string): { readonly start: number; readonly end: number } {
	const start = sourceText.indexOf(primitiveStartMarker);
	const endMarkerStart = sourceText.indexOf(primitiveEndMarker);
	if (start < 0 || endMarkerStart < 0 || endMarkerStart <= start) {
		throw new Error('Canonical CSS must contain one ordered design-primitives marker pair');
	}
	if (
		sourceText.indexOf(primitiveStartMarker, start + primitiveStartMarker.length) >= 0 ||
		sourceText.indexOf(primitiveEndMarker, endMarkerStart + primitiveEndMarker.length) >= 0
	) {
		throw new Error('Canonical CSS must contain exactly one design-primitives marker pair');
	}
	return { start, end: endMarkerStart + primitiveEndMarker.length };
}

function normalizePrimitiveValue(rawValue: string): string {
	const value = rawValue.trim().toLowerCase();
	const shortHexMatch = /^#([0-9a-f]{3}|[0-9a-f]{4})$/u.exec(value);
	if (shortHexMatch?.[1] !== undefined) {
		return `#${shortHexMatch[1]
			.split('')
			.map((character: string): string => character.repeat(2))
			.join('')}`;
	}

	const rgbMatch = /^rgba?\(\s*(\d+)\s+([0-9]+)\s+([0-9]+)\s*\/\s*([0-9.]+)\s*\)$/u.exec(value);
	if (rgbMatch !== null) {
		const red = rgbMatch[1];
		const green = rgbMatch[2];
		const blue = rgbMatch[3];
		const alpha = rgbMatch[4];
		if (red === undefined || green === undefined || blue === undefined || alpha === undefined) {
			throw new Error(`Malformed RGB primitive: ${rawValue}`);
		}
		return `#${toHex(red)}${toHex(green)}${toHex(blue)}@${Number(alpha)}`;
	}

	return value;
}

function toHex(decimalChannel: string): string {
	return Number(decimalChannel).toString(16).padStart(2, '0');
}

function isRawColorExemptPath(relativePath: string): boolean {
	return (
		relativePath === 'src/design-tokens/bridge-design-palette.ts' ||
		/\.(?:test|spec)\.[^.]+$/u.test(relativePath) ||
		relativePath.includes('test-support')
	);
}

function isAllowedBridgeAliasDefinition(
	sourceFile: SourceFileRecord,
	match: IndexedMatch,
): boolean {
	if (sourceFile.relativePath !== 'src/app/bridge-app.css') {
		return false;
	}
	const lineStart = sourceFile.sourceText.lastIndexOf('\n', match.index) + 1;
	const lineEndCandidate = sourceFile.sourceText.indexOf('\n', match.index);
	const lineEnd = lineEndCandidate < 0 ? sourceFile.sourceText.length : lineEndCandidate;
	const line = sourceFile.sourceText.slice(lineStart, lineEnd).trim();
	const aliasDefinitionMatch = /^(--bridge-[a-z0-9_-]+):\s*(?:var\(|color-mix\()/iu.exec(line);
	return aliasDefinitionMatch?.[1] === match.text && allowedBridgeAliasNames.has(match.text);
}

function matchAll(sourceText: string, pattern: RegExp): readonly IndexedMatch[] {
	return [...sourceText.matchAll(pattern)].map((match: RegExpMatchArray): IndexedMatch => {
		if (match.index === undefined) {
			throw new Error(`Pattern did not expose an index: ${pattern.source}`);
		}
		return { index: match.index, text: match[0] };
	});
}

function findingAt(
	sourceFile: SourceFileRecord,
	index: number,
	ruleId: DesignTokenRuleId,
	matchedText: string,
): DesignTokenFinding {
	const location = lineAndColumn(sourceFile.sourceText, index);
	return {
		relativePath: sourceFile.relativePath,
		line: location.line,
		column: location.column,
		ruleId,
		message: `${matchedText} violates ${ruleId}`,
	};
}

function lineAndColumn(
	sourceText: string,
	index: number,
): { readonly line: number; readonly column: number } {
	const prefix = sourceText.slice(0, index);
	const lines = prefix.split('\n');
	return { line: lines.length, column: (lines.at(-1)?.length ?? 0) + 1 };
}

function applyCountAllowlist(
	findings: readonly DesignTokenFinding[],
	allowlist: CountAllowlist,
	ruleId: DesignTokenRuleId,
): readonly DesignTokenFinding[] {
	const findingsByPath = new Map<string, DesignTokenFinding[]>();
	for (const finding of findings) {
		const pathFindings = findingsByPath.get(finding.relativePath) ?? [];
		pathFindings.push(finding);
		findingsByPath.set(finding.relativePath, pathFindings);
	}
	const violations: DesignTokenFinding[] = [];
	const checkedPaths = new Set([...findingsByPath.keys(), ...Object.keys(allowlist)]);
	for (const relativePath of checkedPaths) {
		const pathFindings = findingsByPath.get(relativePath) ?? [];
		const allowedCount = allowlist[relativePath] ?? 0;
		if (pathFindings.length > allowedCount) {
			violations.push(...pathFindings.slice(allowedCount));
		} else if (pathFindings.length === 0 && Object.hasOwn(allowlist, relativePath)) {
			violations.push({
				relativePath,
				line: 1,
				column: 1,
				ruleId,
				message: 'stale allowlist entry — remove the entry',
			});
		} else if (pathFindings.length < allowedCount) {
			violations.push({
				relativePath,
				line: 1,
				column: 1,
				ruleId,
				message: `stale allowlist entry — tighten to ${pathFindings.length}`,
			});
		}
	}
	return violations;
}

function compareFindings(left: DesignTokenFinding, right: DesignTokenFinding): number {
	return (
		left.relativePath.localeCompare(right.relativePath) ||
		left.line - right.line ||
		left.column - right.column ||
		left.ruleId.localeCompare(right.ruleId)
	);
}

function normalizePath(path: string): string {
	return path.replaceAll('\\', '/');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
	const findings = await checkBridgeWebDesignTokens();
	for (const finding of findings) {
		console.error(
			`${finding.relativePath}:${finding.line}:${finding.column} - ${finding.ruleId} - ${finding.message}`,
		);
	}
	if (findings.length > 0) {
		process.exitCode = 1;
	}
}
