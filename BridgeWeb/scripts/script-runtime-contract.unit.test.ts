import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

const packageRootPath = new URL('../', import.meta.url);

describe('script runtime contract', () => {
	test('keeps BridgeWeb scripts in TypeScript', async () => {
		const scriptFileNames = await readScriptFileNames(new URL('scripts/', packageRootPath));
		const scriptExtensions = scriptFileNames
			.filter((fileName: string): boolean => !fileName.endsWith('.unit.test.ts'))
			.map((fileName: string): string => fileName.slice(fileName.lastIndexOf('.')))
			.toSorted();

		expect(scriptExtensions.every((extension: string): boolean => extension === '.ts')).toBe(true);
	});

	test('runs TypeScript scripts through Node type stripping', async () => {
		const scripts = await readPackageScripts();

		expect(scripts['build']).toContain(
			'node --experimental-strip-types scripts/build-app-assets.ts',
		);
		expect(scripts['audit:assets']).toBe(
			'node --experimental-strip-types scripts/audit-dependencies-and-assets.ts',
		);
		expect(scripts['check']).toContain(
			'node --experimental-strip-types scripts/check-bridgeweb-architecture.ts',
		);
		expect(scripts['benchmark:viewer']).toBe('vitest --config vitest.benchmark.config.ts run');
	});

	test('loads the Bridge app Tailwind stylesheet from the WebKit entrypoint', async () => {
		const bootstrapSource = await readFile(
			new URL('src/app/bridge-app-bootstrap.tsx', packageRootPath),
			'utf8',
		);

		expect(bootstrapSource).toContain("import './bridge-app.css';");
	});
});

async function readScriptFileNames(directoryUrl: URL): Promise<readonly string[]> {
	const entries = await readdir(directoryUrl, { withFileTypes: true });
	const fileNames: string[] = [];

	const childDirectoryFileNameGroups = await Promise.all(
		entries
			.filter((entry): boolean => entry.isDirectory())
			.map(async (entry): Promise<readonly string[]> => {
				const childFileNames = await readScriptFileNames(new URL(`${entry.name}/`, directoryUrl));
				return childFileNames.map(
					(childFileName: string): string => `${entry.name}/${childFileName}`,
				);
			}),
	);

	for (const entry of entries) {
		if (!entry.isDirectory()) {
			fileNames.push(entry.name);
		}
	}
	for (const childFileNameGroup of childDirectoryFileNameGroups) {
		fileNames.push(...childFileNameGroup);
	}

	return fileNames;
}

async function readPackageScripts(): Promise<Record<string, string>> {
	const packageJson: unknown = JSON.parse(
		await readFile(join(fileURLToPath(packageRootPath), 'package.json'), 'utf8'),
	);

	if (!isRecord(packageJson) || !isStringRecord(packageJson['scripts'])) {
		throw new Error('package.json scripts must be a string record');
	}

	return packageJson['scripts'];
}

function isStringRecord(value: unknown): value is Record<string, string> {
	if (!isRecord(value)) {
		return false;
	}

	return Object.values(value).every((entry: unknown): boolean => typeof entry === 'string');
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
