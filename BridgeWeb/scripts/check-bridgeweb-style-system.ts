import type { Dirent } from 'node:fs';
import { readdir, readFile as readFileFromDisk } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { analyzeCssSource } from './check-bridgeweb-style-system-css.ts';
import {
	compareStyleSystemFindings,
	evaluationFailure,
	type StyleSystemFinding,
	type StyleSystemReport,
} from './check-bridgeweb-style-system-model.ts';
import {
	analyzeTypeScriptSources,
	createTypeScriptSourceRecord,
	readPaletteMirror,
	type TypeScriptSourceRecord,
	typeScriptParseFindings,
} from './check-bridgeweb-style-system-typescript.ts';

export interface CheckBridgeWebStyleSystemProps {
	readonly packageRootPath?: string;
	readonly readFile?: (filePath: string) => Promise<string>;
}

const defaultPackageRootPath = fileURLToPath(new URL('../', import.meta.url));
const canonicalCssPath = 'src/app/bridge-app.css';
const paletteMirrorPath = 'src/design-tokens/bridge-design-palette.ts';
const checkedExtensions = new Set(['.css', '.ts', '.tsx']);
const ignoredDirectoryNames = new Set(['coverage', 'dist', 'node_modules']);

export async function checkBridgeWebStyleSystem(
	props: CheckBridgeWebStyleSystemProps = {},
): Promise<StyleSystemReport> {
	const packageRootPath = props.packageRootPath ?? defaultPackageRootPath;
	const readFile =
		props.readFile ?? ((filePath: string): Promise<string> => readFileFromDisk(filePath, 'utf8'));
	const findings: StyleSystemFinding[] = [];
	let sourceFilePaths: readonly string[] = [];
	try {
		sourceFilePaths = await collectSourceFiles(join(packageRootPath, 'src'));
	} catch (error: unknown) {
		findings.push(
			evaluationFailure('src', `Cannot enumerate production style scope: ${errorMessage(error)}`),
		);
	}

	const sourceRecords = new Map<string, TypeScriptSourceRecord>();
	const customClassStyleProperties = new Map<string, Set<string>>();
	let canonicalCssEntries: ReadonlyMap<string, string> | null = null;
	let duplicateCssNames: readonly string[] = [];
	await Promise.all(
		sourceFilePaths.map(async (filePath): Promise<void> => {
			const relativePath = normalizePath(relative(packageRootPath, filePath));
			let sourceText: string;
			try {
				sourceText = await readFile(filePath);
			} catch (error: unknown) {
				findings.push(
					evaluationFailure(relativePath, `Cannot read checked source: ${errorMessage(error)}`),
				);
				return;
			}
			if (extname(filePath) === '.css') {
				try {
					const result = analyzeCssSource({
						sourceText,
						relativePath,
						isCanonicalCss: relativePath === canonicalCssPath,
					});
					findings.push(...result.findings);
					mergeCustomClassStyleProperties(
						customClassStyleProperties,
						result.customClassStyleProperties,
					);
					if (relativePath === canonicalCssPath) {
						canonicalCssEntries = result.primitiveEntries;
						duplicateCssNames = result.duplicatePrimitiveNames;
					}
				} catch (error: unknown) {
					findings.push(
						evaluationFailure(relativePath, `CSS parse failed: ${errorMessage(error)}`),
					);
				}
				return;
			}
			const record = createTypeScriptSourceRecord({ sourceText, relativePath });
			sourceRecords.set(relativePath, record);
			findings.push(...typeScriptParseFindings(record));
		}),
	);

	findings.push(...analyzeTypeScriptSources(sourceRecords, customClassStyleProperties));
	findings.push(...paletteParityFindings(canonicalCssEntries, duplicateCssNames, sourceRecords));
	const sortedFindings = findings.toSorted(compareStyleSystemFindings);
	return { ok: sortedFindings.length === 0, findings: sortedFindings };
}

function mergeCustomClassStyleProperties(
	target: Map<string, Set<string>>,
	source: ReadonlyMap<string, ReadonlySet<string>>,
): void {
	for (const [className, sourceProperties] of source) {
		const targetProperties = target.get(className) ?? new Set<string>();
		for (const propertyName of sourceProperties) {
			targetProperties.add(propertyName);
		}
		target.set(className, targetProperties);
	}
}

async function collectSourceFiles(directoryPath: string): Promise<readonly string[]> {
	const entries = await readdir(directoryPath, { withFileTypes: true });
	const groups = await Promise.all(
		entries.map(async (entry: Dirent): Promise<readonly string[]> => {
			const entryPath = join(directoryPath, entry.name);
			if (entry.isDirectory() && !ignoredDirectoryNames.has(entry.name)) {
				return collectSourceFiles(entryPath);
			}
			return entry.isFile() && checkedExtensions.has(extname(entry.name)) ? [entryPath] : [];
		}),
	);
	return groups.flat().toSorted();
}

function paletteParityFindings(
	cssEntries: ReadonlyMap<string, string> | null,
	duplicateCssNames: readonly string[],
	records: ReadonlyMap<string, TypeScriptSourceRecord>,
): readonly StyleSystemFinding[] {
	const findings: StyleSystemFinding[] = [];
	if (cssEntries === null) {
		return [
			evaluationFailure(canonicalCssPath, 'Canonical CSS primitive block could not be evaluated.'),
		];
	}
	const mirrorRecord = records.get(paletteMirrorPath);
	if (mirrorRecord === undefined) {
		return [evaluationFailure(paletteMirrorPath, 'Static palette mirror could not be read.')];
	}
	let mirrorResult: ReturnType<typeof readPaletteMirror>;
	try {
		mirrorResult = readPaletteMirror(mirrorRecord);
	} catch (error: unknown) {
		return [
			evaluationFailure(
				paletteMirrorPath,
				`Static palette mirror is invalid: ${errorMessage(error)}`,
			),
		];
	}
	for (const duplicateName of duplicateCssNames) {
		findings.push(
			paletteFinding(canonicalCssPath, `CSS primitive key is duplicate: ${duplicateName}`),
		);
	}
	for (const duplicateName of mirrorResult.duplicateNames) {
		findings.push(
			paletteFinding(paletteMirrorPath, `Mirror primitive key is duplicate: ${duplicateName}`),
		);
	}
	const allNames = new Set([...cssEntries.keys(), ...mirrorResult.entries.keys()]);
	for (const name of [...allNames].toSorted()) {
		const cssValue = cssEntries.get(name);
		const mirrorValue = mirrorResult.entries.get(name);
		if (cssValue === undefined) {
			findings.push(paletteFinding(paletteMirrorPath, `Mirror has extra primitive ${name}.`));
		} else if (mirrorValue === undefined) {
			findings.push(paletteFinding(paletteMirrorPath, `Mirror is missing primitive ${name}.`));
		} else if (cssValue !== mirrorValue) {
			findings.push(
				paletteFinding(
					paletteMirrorPath,
					`Primitive ${name} differs: CSS=${cssValue}; mirror=${mirrorValue}.`,
				),
			);
		}
	}
	return findings;
}

function paletteFinding(relativePath: string, message: string): StyleSystemFinding {
	return { ruleId: 'palette-parity', relativePath, line: 1, column: 1, message };
}

function normalizePath(path: string): string {
	return path.replaceAll('\\', '/');
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function printReport(report: StyleSystemReport): void {
	for (const finding of report.findings) {
		console.error(
			`${finding.relativePath}:${finding.line}:${finding.column} [${finding.ruleId}] ${finding.message}`,
		);
	}
	if (!report.ok) {
		console.error(`BridgeWeb style-system check failed with ${report.findings.length} finding(s).`);
	}
}

const isDirectExecution =
	process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isDirectExecution) {
	const report = await checkBridgeWebStyleSystem();
	printReport(report);
	if (!report.ok) {
		process.exitCode = 1;
	}
}
