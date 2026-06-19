import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import {
	buildAppAssetManifest,
	createAppIndexHtml,
	normalizePackagedPierreWorkerSource,
	readDependencyLicenseMetadata,
	summarizeAppAssetTotals,
	validatePackagedAppAssetContents,
	validatePackagedAppOutput,
	validateWorkerSourceSelfContained,
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
			await writeFile(join(tempDirectory, 'swift-language.js'), 'console.log("swift");\n', 'utf8');
			await writeFile(join(tempDirectory, 'bridge-app.css'), ':root { color: white; }\n', 'utf8');
			await writeFile(
				join(tempDirectory, 'pierre-worker-portable.js'),
				'self.onmessage = () => {};\n',
				'utf8',
			);

			const manifest = await buildAppAssetManifest({
				appDirectoryPath: tempDirectory,
				mainScriptPath: 'bridge-app.js',
				auxiliaryScriptPaths: ['swift-language.js'],
				stylePaths: ['bridge-app.css'],
				workerAssets: [
					{
						kind: 'pierre-diffs-shiki',
						path: 'pierre-worker-portable.js',
						workerKind: 'classicWorker',
						source: 'packagedAppAsset',
					},
				],
			});

			expect(manifest.schemaVersion).toBe(1);
			expect(manifest.entrypoints.mainScript.path).toBe('bridge-app.js');
			expect(manifest.entrypoints.auxiliaryScripts).toEqual([
				expect.objectContaining({
					path: 'swift-language.js',
					bytes: 22,
				}),
			]);
			expect(manifest.entrypoints.styles).toHaveLength(1);
			expect(manifest.workers).toHaveLength(1);
			const workerAsset = manifest.workers[0];

			expect(workerAsset).toBeDefined();
			expect(workerAsset).toMatchObject({
				kind: 'pierre-diffs-shiki',
				path: 'pierre-worker-portable.js',
				agentStudioAppUrl: 'agentstudio://app/pierre-worker-portable.js',
				workerKind: 'classicWorker',
				source: 'packagedAppAsset',
				bytes: 27,
			});
			expect(workerAsset?.sha256).toMatch(/^[a-f0-9]{64}$/);
		} finally {
			await rm(tempDirectory, { force: true, recursive: true });
		}
	});

	test('summarizes unique packaged asset bytes when a worker is also an auxiliary script', () => {
		const sharedWorkerAsset = {
			path: 'assets/bridge-markdown-render-worker.js',
			bytes: 1_200,
			sha256: 'c'.repeat(64),
		};
		const totals = summarizeAppAssetTotals({
			schemaVersion: 1,
			entrypoints: {
				mainScript: {
					path: 'assets/bridge-app.js',
					bytes: 10_000,
					sha256: 'a'.repeat(64),
				},
				auxiliaryScripts: [
					sharedWorkerAsset,
					{
						path: 'assets/swift-language.js',
						bytes: 300,
						sha256: 'b'.repeat(64),
					},
				],
				styles: [],
			},
			workers: [
				{
					...sharedWorkerAsset,
					kind: 'bridge-markdown-render',
					source: 'packagedAppAsset',
					agentStudioAppUrl: 'agentstudio://app/assets/bridge-markdown-render-worker.js',
					workerKind: 'classicWorker',
				},
			],
		});

		expect(totals).toEqual({
			appBytes: 11_500,
			workerBytes: 1_200,
			totalBytes: 11_500,
			appAssetCount: 3,
			workerAssetCount: 1,
		});
	});

	test('rejects missing worker assets and dev-entry HTML', () => {
		const validWorkerManifest = {
			schemaVersion: 1,
			entrypoints: {
				mainScript: {
					path: 'assets/bridge-app.js',
					bytes: 1,
					sha256: 'a'.repeat(64),
				},
				auxiliaryScripts: [],
				styles: [],
			},
			workers: [
				{
					kind: 'pierre-diffs-shiki',
					path: 'assets/pierre-diffs-worker-portable.js',
					bytes: 1,
					sha256: 'b'.repeat(64),
					source: 'packagedAppAsset',
					agentStudioAppUrl: 'agentstudio://app/assets/pierre-diffs-worker-portable.js',
					workerKind: 'classicWorker',
				},
			],
		} as const;

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
						auxiliaryScripts: [],
						styles: [],
					},
					workers: [],
				},
			}),
		).toThrow(/dev entrypoint/);

		for (const devReference of [
			'/src/app/bridge-app-dev-bootstrap.tsx',
			'bridge-app-dev-fixture',
			'bridge-viewer-mocked-backend',
			'bridge-viewer/test-support',
		]) {
			expect(() =>
				validatePackagedAppOutput({
					indexHtml: `<script type="module" src="${devReference}"></script>`,
					manifest: validWorkerManifest,
				}),
			).toThrow(/dev-only BridgeWeb reference/);
		}
	});

	test('rejects dev-only references inside packaged JavaScript and CSS asset contents', async () => {
		const tempDirectory = await mkdtemp(join(tmpdir(), 'bridge-app-assets-'));

		try {
			await mkdir(join(tempDirectory, 'assets'), { recursive: true });
			await writeFile(
				join(tempDirectory, 'assets/bridge-app.js'),
				'console.log("bridge-viewer/test-support");\n',
				'utf8',
			);
			await writeFile(join(tempDirectory, 'assets/bridge-app.css'), ':root {}\n', 'utf8');
			await writeFile(
				join(tempDirectory, 'assets/pierre-diffs-worker-portable.js'),
				'self.onmessage = () => {};\n',
				'utf8',
			);

			await expect(
				validatePackagedAppAssetContents({
					appDirectoryPath: tempDirectory,
					manifest: {
						schemaVersion: 1,
						entrypoints: {
							mainScript: {
								path: 'assets/bridge-app.js',
								bytes: 1,
								sha256: 'a'.repeat(64),
							},
							auxiliaryScripts: [],
							styles: [
								{
									path: 'assets/bridge-app.css',
									bytes: 1,
									sha256: 'b'.repeat(64),
								},
							],
						},
						workers: [
							{
								kind: 'pierre-diffs-shiki',
								path: 'assets/pierre-diffs-worker-portable.js',
								bytes: 1,
								sha256: 'c'.repeat(64),
								source: 'packagedAppAsset',
								agentStudioAppUrl: 'agentstudio://app/assets/pierre-diffs-worker-portable.js',
								workerKind: 'classicWorker',
							},
						],
					},
				}),
			).rejects.toThrow(/dev-only BridgeWeb reference/);
		} finally {
			await rm(tempDirectory, { force: true, recursive: true });
		}
	});

	test('rejects dev-only references inside packaged worker asset contents', async () => {
		const tempDirectory = await mkdtemp(join(tmpdir(), 'bridge-app-assets-'));

		try {
			await mkdir(join(tempDirectory, 'assets'), { recursive: true });
			await writeFile(join(tempDirectory, 'assets/bridge-app.js'), 'console.log("app");\n', 'utf8');
			await writeFile(join(tempDirectory, 'assets/bridge-app.css'), ':root {}\n', 'utf8');
			await writeFile(
				join(tempDirectory, 'assets/pierre-diffs-worker-portable.js'),
				'console.log("review-viewer/test-support");\n',
				'utf8',
			);

			await expect(
				validatePackagedAppAssetContents({
					appDirectoryPath: tempDirectory,
					manifest: {
						schemaVersion: 1,
						entrypoints: {
							mainScript: {
								path: 'assets/bridge-app.js',
								bytes: 1,
								sha256: 'a'.repeat(64),
							},
							auxiliaryScripts: [],
							styles: [
								{
									path: 'assets/bridge-app.css',
									bytes: 1,
									sha256: 'b'.repeat(64),
								},
							],
						},
						workers: [
							{
								kind: 'pierre-diffs-shiki',
								path: 'assets/pierre-diffs-worker-portable.js',
								bytes: 1,
								sha256: 'c'.repeat(64),
								source: 'packagedAppAsset',
								agentStudioAppUrl: 'agentstudio://app/assets/pierre-diffs-worker-portable.js',
								workerKind: 'classicWorker',
							},
						],
					},
				}),
			).rejects.toThrow(/dev-only BridgeWeb reference/);
		} finally {
			await rm(tempDirectory, { force: true, recursive: true });
		}
	});

	test('rejects external resource loads inside packaged CSS assets', async () => {
		await Promise.all(
			[
				'@import "https://example.invalid/theme.css";\n',
				'.hero { background: url(https://example.invalid/bg.png); }\n',
			].map(async (cssContent: string): Promise<void> => {
				const tempDirectory = await mkdtemp(join(tmpdir(), 'bridge-app-assets-'));

				try {
					await mkdir(join(tempDirectory, 'assets'), { recursive: true });
					await writeFile(
						join(tempDirectory, 'assets/bridge-app.js'),
						'console.log("app");\n',
						'utf8',
					);
					await writeFile(
						join(tempDirectory, 'assets/pierre-diffs-worker-portable.js'),
						'self.onmessage = () => {};\n',
						'utf8',
					);
					await writeFile(join(tempDirectory, 'assets/bridge-app.css'), cssContent, 'utf8');

					await expect(
						validatePackagedAppAssetContents({
							appDirectoryPath: tempDirectory,
							manifest: {
								schemaVersion: 1,
								entrypoints: {
									mainScript: {
										path: 'assets/bridge-app.js',
										bytes: 1,
										sha256: 'a'.repeat(64),
									},
									auxiliaryScripts: [],
									styles: [
										{
											path: 'assets/bridge-app.css',
											bytes: 1,
											sha256: 'b'.repeat(64),
										},
									],
								},
								workers: [
									{
										kind: 'pierre-diffs-shiki',
										path: 'assets/pierre-diffs-worker-portable.js',
										bytes: 1,
										sha256: 'c'.repeat(64),
										source: 'packagedAppAsset',
										agentStudioAppUrl: 'agentstudio://app/assets/pierre-diffs-worker-portable.js',
										workerKind: 'classicWorker',
									},
								],
							},
						}),
					).rejects.toThrow(/external resource load/);
				} finally {
					await rm(tempDirectory, { force: true, recursive: true });
				}
			}),
		);
	});

	test('validates packaged worker sources stay self contained for blob-backed WebKit workers', () => {
		expect(
			validateWorkerSourceSelfContained(
				'const wasmBytes = new Uint8Array([]); WebAssembly.instantiate(wasmBytes);',
			),
		).toEqual(
			expect.objectContaining({
				isSelfContained: true,
			}),
		);

		for (const source of [
			'import "sidecar.js";',
			'import("https://example.invalid/sidecar.js");',
			'importScripts("sidecar.js");',
			'fetch("./sidecar.wasm");',
			'new URL("./sidecar.wasm", import.meta.url);',
			'new XMLHttpRequest();',
		]) {
			expect(() => validateWorkerSourceSelfContained(source)).toThrow(/self-contained/);
		}
	});

	test('normalizes Pierre worker optional Shiki WASM sidecar import', () => {
		const normalizedSource = normalizePackagedPierreWorkerSource(`
			const engine = createOnigurumaEngine(import("./wasm-qE0LgnY3.js"));
		`);

		expect(normalizedSource).not.toContain('import("./wasm-qE0LgnY3.js")');
		expect(normalizedSource).toContain('BridgeWeb packages only the shiki-js worker highlighter');
		expect(() => validateWorkerSourceSelfContained(normalizedSource)).not.toThrow();
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
