import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import {
	buildAppAssetManifest,
	createAppIndexHtml,
	readDependencyLicenseMetadata,
	validatePackagedAppOutput,
} from './app-asset-contract.ts';

describe('app asset contract', () => {
	test('renders packaged HTML with built assets instead of the dev entrypoint', () => {
		const html = createAppIndexHtml({
			mainScriptPath: 'assets/bridge-app-abc123.js',
			stylePaths: ['assets/bridge-app-def456.css'],
		});

		expect(html).toContain('<script type="module" src="./assets/bridge-app-abc123.js"></script>');
		expect(html).toContain('<link rel="stylesheet" href="./assets/bridge-app-def456.css">');
		expect(html).not.toContain('/src/app/bridge-app-bootstrap.tsx');
	});

	test('records package asset sizes and hashes for app and worker assets', async () => {
		const tempDirectory = await mkdtemp(join(tmpdir(), 'bridge-app-assets-'));

		try {
			await writeFile(join(tempDirectory, 'bridge-app.js'), 'console.log("app");\n', 'utf8');
			await writeFile(join(tempDirectory, 'bridge-app.css'), ':root { color: white; }\n', 'utf8');
			await writeFile(
				join(tempDirectory, 'pierre-worker-portable.js'),
				'self.onmessage = () => {};\n',
				'utf8',
			);

			const manifest = await buildAppAssetManifest({
				appDirectoryPath: tempDirectory,
				mainScriptPath: 'bridge-app.js',
				stylePaths: ['bridge-app.css'],
				workerAssets: [
					{
						kind: 'pierre-diffs-shiki',
						path: 'pierre-worker-portable.js',
						source: 'packagedAppAsset',
					},
				],
			});

			expect(manifest.schemaVersion).toBe(1);
			expect(manifest.entrypoints.mainScript.path).toBe('bridge-app.js');
			expect(manifest.entrypoints.styles).toHaveLength(1);
			expect(manifest.workers).toHaveLength(1);
			const workerAsset = manifest.workers[0];

			expect(workerAsset).toBeDefined();
			expect(workerAsset).toMatchObject({
				kind: 'pierre-diffs-shiki',
				path: 'pierre-worker-portable.js',
				source: 'packagedAppAsset',
				bytes: 27,
			});
			expect(workerAsset?.sha256).toMatch(/^[a-f0-9]{64}$/);
		} finally {
			await rm(tempDirectory, { force: true, recursive: true });
		}
	});

	test('rejects missing worker assets and dev-entry HTML', () => {
		expect(() =>
			validatePackagedAppOutput({
				indexHtml: '<script type="module" src="/src/app/bridge-app-bootstrap.tsx"></script>',
				manifest: {
					schemaVersion: 1,
					entrypoints: {
						mainScript: {
							path: 'assets/bridge-app.js',
							bytes: 1,
							sha256: 'a'.repeat(64),
						},
						styles: [],
					},
					workers: [],
				},
			}),
		).toThrow(/dev entrypoint/);
	});

	test('reads installed dependency version and license metadata', async () => {
		const tempDirectory = await mkdtemp(join(tmpdir(), 'bridge-dependency-metadata-'));

		try {
			await mkdir(join(tempDirectory, 'node_modules/@scope/package'), { recursive: true });
			await writeFile(
				join(tempDirectory, 'package.json'),
				JSON.stringify({
					dependencies: {
						'@scope/package': '1.2.3',
					},
				}),
				'utf8',
			);
			await writeFile(
				join(tempDirectory, 'node_modules/@scope/package/package.json'),
				JSON.stringify({
					name: '@scope/package',
					version: '1.2.3',
					license: 'MIT',
				}),
				'utf8',
			);

			await expect(
				readDependencyLicenseMetadata({
					packageRootPath: tempDirectory,
					packageNames: ['@scope/package'],
				}),
			).resolves.toEqual([
				{
					name: '@scope/package',
					requestedVersion: '1.2.3',
					installedVersion: '1.2.3',
					license: 'MIT',
				},
			]);
		} finally {
			await rm(tempDirectory, { force: true, recursive: true });
		}
	});
});
