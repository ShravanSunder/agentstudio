import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { dirname, join, resolve } from 'node:path';

import type { Plugin } from 'vite';
import type { BrowserCommand } from 'vitest/node';
import { z } from 'zod';

import {
	createBridgeProductDevCarrier,
	type BridgeProductDevCarrier,
	type BridgeProductDevContentLoadObservation,
} from '../scripts/dev-server/bridge-product-dev-carrier.js';
import { BridgeProductDevReviewAdapter } from '../scripts/dev-server/bridge-product-dev-review-adapter.js';
import {
	createBridgeWorktreeDevProvider,
	loadBridgeWorktreeDevMetadataSnapshot,
	type BridgeWorktreeDevProviderConfig,
} from '../scripts/dev-server/bridge-worktree-dev-provider.js';
import {
	bridgeProductSourceCellOracleSchema,
	bridgeProductSourceCellPaintReportSchema,
	type BridgeProductSourceCellOracle,
	type BridgeProductSourceCellPaintReport,
	type BridgeProductSourceCellProjectName,
	type BridgeProductSourceCellSourceKind,
} from '../src/app/bridge-app-product-source-cell-contract.js';
import type {
	BridgeProductFileContentDescriptor,
	BridgeProductReviewContentDescriptor,
} from '../src/core/comm-worker/bridge-product-content-contracts.js';
import { BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE } from '../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_CONTENT_ROUTE,
	BRIDGE_PRODUCT_STREAM_ROUTE,
} from '../src/core/comm-worker/bridge-product-dev-routes.js';

const sourceCellMetadataRoute = '/__bridge-source-cell/metadata';
const sourceCellOracleRoute = '/__bridge-source-cell/oracle';
const sourceCellTraceRoute = '/__bridge-source-cell/trace';
const deterministicFixtureBaseRef = 'HEAD';
const deterministicFixtureFilePath = 'src/00-file-final.ts';
const sourceCellPackageManifestSchema = z
	.object({ dependencies: z.record(z.string(), z.string()).optional() })
	.loose();

interface BridgeSourceCellContentTraceEntry {
	readonly contentRequestId: string;
	readonly descriptorId: string;
	readonly itemId: string;
	readonly observedSha256: string;
	readonly paneSessionId: string;
	readonly role: string;
	readonly sourceGeneration: number;
	readonly sourceIdentity: string;
	readonly surface: 'file' | 'review';
	readonly workerInstanceId: string;
}

interface BridgeSourceCellPreparedContext {
	readonly bundledPierreVersion: string;
	readonly contentTrace: BridgeSourceCellContentTraceEntry[];
	readonly oracle: BridgeProductSourceCellOracle;
	readonly packageRoot: string;
	readonly projectName: BridgeProductSourceCellProjectName;
	readonly providerConfig: BridgeWorktreeDevProviderConfig;
	readonly providerIdentity: string;
	readonly providerProcessId: number;
	readonly reportPath: string;
	readonly requestTrace: string[];
	readonly runMarker: string;
	readonly sourceKind: BridgeProductSourceCellSourceKind;
	readonly testEntry: string;
}

export interface BridgeSourceCellHarness {
	readonly browserCommands: {
		readonly bridgeInstallSourceCellNetworkProbe: BrowserCommand<[]>;
		readonly bridgeReadSourceCellNetworkFailures: BrowserCommand<[]>;
		readonly bridgeWriteSourceCellReport: BrowserCommand<[report: unknown]>;
	};
	readonly plugin: Plugin;
}

export function createBridgeSourceCellHarness(props: {
	readonly packageRoot: string;
	readonly projectName: BridgeProductSourceCellProjectName;
	readonly sourceKind: BridgeProductSourceCellSourceKind;
	readonly testEntry: string;
}): BridgeSourceCellHarness {
	const runMarker = `${Date.now().toString(36)}-${randomUUID()}`;
	const networkFailures: string[] = [];
	let networkProbeInstalled = false;
	let preparedContextPromise: Promise<BridgeSourceCellPreparedContext> | null = null;
	const preparedContext = (): Promise<BridgeSourceCellPreparedContext> => {
		preparedContextPromise ??= prepareBridgeSourceCellContext({ ...props, runMarker });
		return preparedContextPromise;
	};
	return {
		browserCommands: {
			bridgeInstallSourceCellNetworkProbe: (commandContext): void => {
				if (networkProbeInstalled) return;
				networkProbeInstalled = true;
				commandContext.context.on('requestfailed', (request): void => {
					if (!request.url().includes('/__bridge-product/')) return;
					networkFailures.push(
						`${request.method()} ${request.url()} -> ${request.failure()?.errorText ?? 'unknown failure'}`,
					);
				});
			},
			bridgeReadSourceCellNetworkFailures: (): readonly string[] => [...networkFailures],
			bridgeWriteSourceCellReport: async (commandContext, reportValue): Promise<string> => {
				const context = await preparedContext();
				const report = bridgeProductSourceCellPaintReportSchema.parse(reportValue);
				const expectedBrowserProjectName = `${context.projectName} (chromium)`;
				if (commandContext.project.name !== expectedBrowserProjectName) {
					throw new Error('Bridge source-cell report command ran in the wrong Vitest project.');
				}
				if (
					resolve(commandContext.testPath ?? '') !== resolve(context.packageRoot, context.testEntry)
				) {
					throw new Error('Bridge source-cell report command ran from the wrong test entry.');
				}
				assertReportMatchesPreparedContext(report, context);
				await mkdir(dirname(context.reportPath), { recursive: true });
				await writeFile(context.reportPath, `${JSON.stringify(report, null, 2)}\n`, {
					encoding: 'utf8',
					flag: 'wx',
				});
				return context.reportPath;
			},
		},
		plugin: {
			name: `bridge-source-cell-${props.projectName}`,
			configureServer(server) {
				let carrierPromise: ReturnType<typeof createSourceCellCarrier> | null = null;
				const carrier = async (): Promise<BridgeProductDevCarrier> => {
					const context = await preparedContext();
					carrierPromise ??= createSourceCellCarrier(context);
					return await carrierPromise;
				};
				server.middlewares.use((request, response, next): void => {
					const requestUrl = request.url ?? '';
					if (requestUrl.startsWith('/__bridge-product/')) {
						const requestMethod = request.method ?? 'UNKNOWN';
						response.once('finish', (): void => {
							void preparedContext().then((context): void => {
								context.requestTrace.push(
									`${requestMethod} ${requestUrl} -> ${String(response.statusCode)}`,
								);
							});
						});
					}
					next();
				});
				server.middlewares.use(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE, (request, response) => {
					runSourceCellMiddleware(
						carrier().then((value) => value.handleBootstrapRequest({ request, response })),
						response,
						{ preparedContext, request },
					);
				});
				server.middlewares.use(BRIDGE_PRODUCT_COMMAND_ROUTE, (request, response) => {
					runSourceCellMiddleware(
						carrier().then((value) => value.handleCommandRequest({ request, response })),
						response,
						{ preparedContext, request },
					);
				});
				server.middlewares.use(BRIDGE_PRODUCT_STREAM_ROUTE, (request, response) => {
					runSourceCellMiddleware(
						carrier().then((value) => value.handleStreamRequest({ request, response })),
						response,
						{ preparedContext, request },
					);
				});
				server.middlewares.use(BRIDGE_PRODUCT_CONTENT_ROUTE, (request, response) => {
					runSourceCellMiddleware(
						carrier().then((value) => value.handleContentRequest({ request, response })),
						response,
						{ preparedContext, request },
					);
				});
				server.middlewares.use(sourceCellMetadataRoute, (request, response) => {
					runSourceCellMiddleware(
						preparedContext().then((context) => {
							writeJsonResponse(request, response, sourceCellMetadata(context));
						}),
						response,
					);
				});
				server.middlewares.use(sourceCellOracleRoute, (request, response) => {
					runSourceCellMiddleware(
						preparedContext().then((context) => {
							writeJsonResponse(request, response, context.oracle);
						}),
						response,
					);
				});
				server.middlewares.use(sourceCellTraceRoute, (request, response) => {
					runSourceCellMiddleware(
						preparedContext().then((context) => {
							writeJsonResponse(request, response, {
								entries: context.contentTrace,
								requests: context.requestTrace,
							});
						}),
						response,
					);
				});
				server.httpServer?.once('close', (): void => {
					void carrierPromise?.then((value) => value.dispose());
				});
			},
		},
	};
}

async function prepareBridgeSourceCellContext(props: {
	readonly packageRoot: string;
	readonly projectName: BridgeProductSourceCellProjectName;
	readonly runMarker: string;
	readonly sourceKind: BridgeProductSourceCellSourceKind;
	readonly testEntry: string;
}): Promise<BridgeSourceCellPreparedContext> {
	if (props.sourceKind !== 'deterministicFixture') {
		throw new Error('The real-worktree source-cell context is not installed yet.');
	}
	const proofRoot = resolve(props.packageRoot, '..', 'tmp', 'bridge-viewer-proof', props.runMarker);
	const fixtureRoot = join(proofRoot, 'fixtures', props.projectName);
	await createDeterministicSourceCellRepository(fixtureRoot);
	const snapshot = await loadBridgeWorktreeDevMetadataSnapshot({
		baseRef: deterministicFixtureBaseRef,
		worktreeRoot: fixtureRoot,
	});
	const reviewSourceIdentity = `dev-review-source-${snapshot.fingerprint.slice(0, 24)}`;
	const entries = await deterministicOracleEntries({ fixtureRoot, reviewSourceIdentity });
	const sourceChecksum = sha256(JSON.stringify(entries));
	const parsedOracle = bridgeProductSourceCellOracleSchema.parse({
		entries,
		oracleKind: 'fixtureManifest',
		runMarker: props.runMarker,
		sourceChecksum,
		sourceKind: props.sourceKind,
	});
	const reportPath = join(proofRoot, props.projectName, 'report.json');
	await mkdir(dirname(reportPath), { recursive: true });
	await writeFile(
		join(dirname(reportPath), 'oracle.json'),
		`${JSON.stringify(parsedOracle, null, 2)}\n`,
		{ encoding: 'utf8', flag: 'wx' },
	);
	const packageJson = sourceCellPackageManifestSchema.parse(
		JSON.parse(await readFile(join(props.packageRoot, 'package.json'), 'utf8')),
	);
	return {
		bundledPierreVersion: packageJson.dependencies?.['@pierre/diffs'] ?? 'unknown',
		contentTrace: [],
		oracle: parsedOracle,
		packageRoot: props.packageRoot,
		projectName: props.projectName,
		providerConfig: {
			baseRef: deterministicFixtureBaseRef,
			scenarioName: 'current-worktree',
			worktreeRoot: fixtureRoot,
		},
		providerIdentity: `vitest-source-cell-${props.projectName}-${props.runMarker}`,
		providerProcessId: process.pid,
		reportPath,
		requestTrace: [],
		runMarker: props.runMarker,
		sourceKind: props.sourceKind,
		testEntry: props.testEntry,
	};
}

async function createSourceCellCarrier(
	context: BridgeSourceCellPreparedContext,
): Promise<BridgeProductDevCarrier> {
	const provider = await createBridgeWorktreeDevProvider(context.providerConfig);
	return createBridgeProductDevCarrier({
		createReviewAdapter: (config) => new BridgeProductDevReviewAdapter(config),
		getFileProvider: async () => provider,
		getReviewSourceConfig: async () => context.providerConfig,
		onContentLoaded: (observation): void => {
			context.contentTrace.push(contentTraceEntry(observation));
		},
	});
}

function contentTraceEntry(
	observation: BridgeProductDevContentLoadObservation,
): BridgeSourceCellContentTraceEntry {
	const descriptor = observation.request.descriptor;
	if (descriptor.contentKind === 'file.content') {
		return {
			contentRequestId: observation.request.contentRequestId,
			descriptorId: descriptor.descriptorId,
			itemId: sourceCellItemId(descriptor),
			observedSha256: sha256(observation.content.bytes),
			paneSessionId: observation.request.paneSessionId,
			role: 'file',
			sourceGeneration: descriptor.source.subscriptionGeneration,
			sourceIdentity: descriptor.source.sourceId,
			surface: 'file',
			workerInstanceId: observation.request.workerInstanceId,
		};
	}
	return {
		contentRequestId: observation.request.contentRequestId,
		descriptorId: descriptor.descriptorId,
		itemId: sourceCellItemId(descriptor),
		observedSha256: sha256(observation.content.bytes),
		paneSessionId: observation.request.paneSessionId,
		role: descriptor.role,
		sourceGeneration: descriptor.reviewGeneration,
		sourceIdentity: descriptor.sourceIdentity,
		surface: 'review',
		workerInstanceId: observation.request.workerInstanceId,
	};
}

function sourceCellItemId(
	descriptor: BridgeProductFileContentDescriptor | BridgeProductReviewContentDescriptor,
): string {
	return descriptor.contentKind === 'file.content' ? descriptor.fileId : descriptor.itemId;
}

async function deterministicOracleEntries(props: {
	readonly fixtureRoot: string;
	readonly reviewSourceIdentity: string;
}): Promise<BridgeProductSourceCellOracle['entries']> {
	const fixtures = deterministicHeadFixtures();
	const reviewEntries = await Promise.all(
		fixtures.map(async (fixture) => ({
			canaryText: fixture.reviewCanary ?? fixture.canary,
			itemId: reviewItemId(fixture.path),
			role: 'head',
			sha256: sha256(await readFile(join(props.fixtureRoot, fixture.path))),
			sourceGeneration: 1,
			sourceIdentity: props.reviewSourceIdentity,
			surface: 'review' as const,
		})),
	);
	const fileFixture = fixtures.find((fixture) => fixture.path === deterministicFixtureFilePath);
	if (fileFixture === undefined) throw new Error('Bridge source-cell File fixture is missing.');
	return [
		...reviewEntries,
		{
			canaryText: fileFixture.canary,
			itemId: `dev-file-id-${sha256(fileFixture.path).slice(0, 16)}`,
			role: 'file',
			sha256: sha256(await readFile(join(props.fixtureRoot, fileFixture.path))),
			sourceGeneration: 1,
			sourceIdentity: 'dev-worktree-source',
			surface: 'file',
		},
	];
}

async function createDeterministicSourceCellRepository(fixtureRoot: string): Promise<void> {
	await mkdir(join(fixtureRoot, 'src'), { recursive: true });
	for (const fixture of deterministicBaseFixtures()) {
		// oxlint-disable-next-line no-await-in-loop -- Fixture writes are intentionally ordered before Git snapshots them.
		await mkdir(dirname(join(fixtureRoot, fixture.path)), { recursive: true });
		// oxlint-disable-next-line no-await-in-loop -- Fixture writes are intentionally ordered before Git snapshots them.
		await writeFile(join(fixtureRoot, fixture.path), fixture.contents, 'utf8');
	}
	await runGit(fixtureRoot, ['init', '--quiet']);
	await runGit(fixtureRoot, ['config', 'user.email', 'bridge-source-cell@example.invalid']);
	await runGit(fixtureRoot, ['config', 'user.name', 'Bridge Source Cell']);
	await runGit(fixtureRoot, ['add', '--all']);
	await runGit(fixtureRoot, [
		'-c',
		'commit.gpgsign=false',
		'commit',
		'--quiet',
		'-m',
		'source-cell-base',
	]);
	for (const fixture of deterministicHeadFixtures()) {
		// oxlint-disable-next-line no-await-in-loop -- Worktree mutations are intentionally ordered after the base commit.
		await writeFile(join(fixtureRoot, fixture.path), fixture.contents, 'utf8');
	}
}

function deterministicBaseFixtures(): readonly SourceCellFixture[] {
	return deterministicHeadFixtures().map((fixture) => ({
		canary: fixture.canary,
		contents: `export const baseValue = '${fixture.path} base';\n`,
		path: fixture.path,
	}));
}

function deterministicHeadFixtures(): readonly SourceCellFixture[] {
	return [
		{
			canary: 'SOURCE_CELL_FILE_FINAL_CANARY',
			contents: sourceCellFixtureContents({
				exportName: 'fileFinal',
				finalCanary: 'SOURCE_CELL_FILE_FINAL_CANARY',
				topCanary: 'SOURCE_CELL_REVIEW_EARLY_CANARY',
			}),
			path: deterministicFixtureFilePath,
			reviewCanary: 'SOURCE_CELL_REVIEW_EARLY_CANARY',
		},
		{
			canary: 'SOURCE_CELL_REVIEW_EARLY_CANARY',
			contents: sourceCellFixtureContents({
				exportName: 'reviewEarly',
				finalCanary: 'SOURCE_CELL_REVIEW_EARLY_CANARY',
			}),
			path: 'src/alpha/10-review-early.ts',
		},
		{
			canary: 'SOURCE_CELL_REVIEW_MIDDLE_CANARY',
			contents: sourceCellFixtureContents({
				exportName: 'reviewMiddle',
				finalCanary: 'SOURCE_CELL_REVIEW_MIDDLE_CANARY',
			}),
			path: 'src/beta/20-review-middle.ts',
		},
		{
			canary: 'SOURCE_CELL_REVIEW_FINAL_CANARY',
			contents: sourceCellFixtureContents({
				exportName: 'reviewFinal',
				finalCanary: 'SOURCE_CELL_REVIEW_FINAL_CANARY',
			}),
			path: 'src/gamma/30-review-final.ts',
		},
	];
}

function sourceCellFixtureContents(props: {
	readonly exportName: string;
	readonly finalCanary: string;
	readonly topCanary?: string;
}): string {
	const body = Array.from(
		{ length: 160 },
		(_unused, lineIndex): string =>
			`export const ${props.exportName}Line${String(lineIndex).padStart(3, '0')} = ${String(lineIndex)};`,
	);
	const topCanary =
		props.topCanary === undefined
			? []
			: [`export const ${props.exportName}TopCanary = '${props.topCanary}';`];
	return `${[...topCanary, ...body].join('\n')}\nexport const ${props.exportName}Canary = '${props.finalCanary}';`;
}

interface SourceCellFixture {
	readonly canary: string;
	readonly contents: string;
	readonly path: string;
	readonly reviewCanary?: string;
}

function reviewItemId(path: string): string {
	return `review-item-${sha256(path).slice(0, 32)}`;
}

function sha256(value: string | Uint8Array): string {
	return createHash('sha256').update(value).digest('hex');
}

async function runGit(cwd: string, args: readonly string[]): Promise<void> {
	await new Promise<void>((resolvePromise, rejectPromise) => {
		const child = spawn('git', [...args], { cwd, stdio: ['ignore', 'ignore', 'pipe'] });
		const errorChunks: Buffer[] = [];
		child.stderr.on('data', (chunk: Buffer): void => {
			errorChunks.push(chunk);
		});
		child.once('error', rejectPromise);
		child.once('close', (exitCode): void => {
			if (exitCode === 0) {
				resolvePromise();
				return;
			}
			rejectPromise(
				new Error(
					`Bridge source-cell git fixture command failed (${String(exitCode)}): ${Buffer.concat(errorChunks).toString('utf8')}`,
				),
			);
		});
	});
}

function sourceCellMetadata(context: BridgeSourceCellPreparedContext): object {
	return {
		bundledPierreVersion: context.bundledPierreVersion,
		oracleUrl: sourceCellOracleRoute,
		projectName: context.projectName,
		providerIdentity: context.providerIdentity,
		providerProcessId: context.providerProcessId,
		runMarker: context.runMarker,
		sourceChecksum: context.oracle.sourceChecksum,
		sourceKind: context.sourceKind,
		testEntry: context.testEntry,
	};
}

function assertReportMatchesPreparedContext(
	report: BridgeProductSourceCellPaintReport,
	context: BridgeSourceCellPreparedContext,
): void {
	const mismatchedField = (
		[
			['bundledPierreVersion', context.bundledPierreVersion],
			['oracleUrl', sourceCellOracleRoute],
			['projectName', context.projectName],
			['providerIdentity', context.providerIdentity],
			['providerProcessId', context.providerProcessId],
			['runMarker', context.runMarker],
			['sourceChecksum', context.oracle.sourceChecksum],
			['sourceKind', context.sourceKind],
			['testEntry', context.testEntry],
		] as const
	).find(([key, value]): boolean => report[key] !== value)?.[0];
	if (mismatchedField !== undefined) {
		throw new Error(
			`Bridge source-cell report ${mismatchedField} does not match its server context.`,
		);
	}
}

function writeJsonResponse(
	request: IncomingMessage,
	response: ServerResponse,
	body: unknown,
): void {
	if (request.method !== 'GET') {
		response.statusCode = 405;
		response.end('Method Not Allowed');
		return;
	}
	response.statusCode = 200;
	response.setHeader('Cache-Control', 'no-store');
	response.setHeader('Content-Type', 'application/json; charset=utf-8');
	response.end(JSON.stringify(body));
}

function runSourceCellMiddleware(
	operation: Promise<void>,
	response: ServerResponse,
	requestTrace?: {
		readonly preparedContext: () => Promise<BridgeSourceCellPreparedContext>;
		readonly request: IncomingMessage;
	},
): void {
	void operation.then(
		async (): Promise<void> => {
			if (requestTrace !== undefined) {
				recordSourceCellRequest(
					await requestTrace.preparedContext(),
					requestTrace.request,
					response,
				);
			}
		},
		async (error: unknown): Promise<void> => {
			if (response.headersSent) {
				response.destroy(error instanceof Error ? error : undefined);
			} else {
				response.statusCode = 500;
				response.setHeader('Content-Type', 'text/plain; charset=utf-8');
				response.end('Bridge source-cell harness failed.');
			}
			if (requestTrace !== undefined) {
				recordSourceCellRequest(
					await requestTrace.preparedContext(),
					requestTrace.request,
					response,
				);
			}
		},
	);
}

function recordSourceCellRequest(
	context: BridgeSourceCellPreparedContext,
	request: IncomingMessage,
	response: ServerResponse,
): void {
	context.requestTrace.push(
		`${request.method ?? 'UNKNOWN'} ${request.url ?? ''} -> ${String(response.statusCode)}`,
	);
}
