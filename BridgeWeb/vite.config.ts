import { Buffer } from 'node:buffer';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { dirname } from 'node:path';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

import {
	buildBridgeDevContentResponseTelemetryBatch,
	createBridgeDevTelemetrySink,
	type BridgeDevTelemetrySink,
	type BridgeDevTelemetrySnapshot,
} from './scripts/dev-server/bridge-dev-telemetry.js';
import {
	createBridgeWorktreeDevProvider,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProvider,
	type BridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProviderWorktreeFileContentRequest,
	type BridgeWorktreeDevProviderWorktreeFileDescriptorRequest,
} from './scripts/dev-server/bridge-worktree-dev-provider.js';
import {
	createBridgeWorktreeReviewDevProvider,
	type BridgeWorktreeReviewDevProvider,
	type BridgeWorktreeReviewContentRequest,
} from './scripts/dev-server/bridge-worktree-review-dev-provider.js';

type BridgeWorktreeDevProviderPromise = Promise<BridgeWorktreeDevProvider>;
type BridgeWorktreeReviewDevProviderPromise = Promise<BridgeWorktreeReviewDevProvider>;

const bridgeWebPackageRoot = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
	base: './',
	resolve: {
		alias: {
			'@': `${bridgeWebPackageRoot}/src`,
		},
	},
	plugins: [
		react(),
		{
			name: 'bridge-worktree-dev-provider',
			configureServer(server) {
				const telemetrySink = createBridgeDevTelemetrySink();
				const providerPromisesByConfig = new Map<string, BridgeWorktreeDevProviderPromise>();
				const providerConfigPromisesByCacheKey = new Map<
					string,
					Promise<BridgeWorktreeDevProviderConfig>
				>();
				const reviewProviderPromisesByConfig = new Map<
					string,
					BridgeWorktreeReviewDevProviderPromise
				>();
				const getProviderConfig = async (
					requestUrl: string | null,
				): Promise<BridgeWorktreeDevProviderConfig> => {
					const cacheKey = bridgeWorktreeDevProviderConfigCacheKey({
						env: process.env,
						requestUrl,
					});
					if (cacheKey === null) {
						return await resolveBridgeWorktreeDevProviderConfig({
							env: process.env,
							packageRoot: bridgeWebPackageRoot,
							requestUrl,
						});
					}
					const existingConfigPromise = providerConfigPromisesByCacheKey.get(cacheKey);
					if (existingConfigPromise !== undefined) {
						return await existingConfigPromise;
					}
					const configPromise = resolveBridgeWorktreeDevProviderConfig({
						env: process.env,
						packageRoot: bridgeWebPackageRoot,
						requestUrl,
					});
					providerConfigPromisesByCacheKey.set(cacheKey, configPromise);
					return await configPromise;
				};
				const getProvider = async (requestUrl: string | null): BridgeWorktreeDevProviderPromise => {
					const config = await getProviderConfig(requestUrl);
					const configKey = `${config.scenarioName}\u0000${config.worktreeRoot}\u0000${config.baseRef}`;
					const existingProviderPromise = providerPromisesByConfig.get(configKey);
					if (existingProviderPromise !== undefined) {
						return existingProviderPromise;
					}
					const providerPromise = createBridgeWorktreeDevProvider(config);
					providerPromisesByConfig.set(configKey, providerPromise);
					return providerPromise;
				};
				const getReviewProvider = async (
					requestUrl: string | null,
				): BridgeWorktreeReviewDevProviderPromise => {
					const config = await getProviderConfig(requestUrl);
					const configKey = `${config.scenarioName}\u0000${config.worktreeRoot}\u0000${config.baseRef}`;
					const existingProviderPromise = reviewProviderPromisesByConfig.get(configKey);
					if (existingProviderPromise !== undefined) {
						return existingProviderPromise;
					}
					const providerPromise = Promise.resolve(createBridgeWorktreeReviewDevProvider(config));
					reviewProviderPromisesByConfig.set(configKey, providerPromise);
					return providerPromise;
				};
				server.middlewares.use('/__bridge-worktree/surface', (request, response) => {
					void handleBridgeWorktreeSurfaceRequest({
						getProvider,
						request,
						response,
					});
				});
				server.middlewares.use('/__bridge-worktree/file-descriptor', (request, response) => {
					void handleBridgeWorktreeFileDescriptorRequest({
						getProvider,
						request,
						response,
					});
				});
				server.middlewares.use('/__bridge-worktree/file-content', (request, response) => {
					void handleBridgeWorktreeFileContentRequest({
						getProvider,
						request,
						response,
						telemetrySink,
					});
				});
				server.middlewares.use('/__bridge-worktree/review-metadata', (request, response) => {
					void handleBridgeWorktreeReviewMetadataRequest({
						getReviewProvider,
						request,
						response,
					});
				});
				server.middlewares.use('/__bridge-worktree/review-content', (request, response) => {
					void handleBridgeWorktreeReviewContentRequest({
						getReviewProvider,
						request,
						response,
						telemetrySink,
					});
				});
				server.middlewares.use('/__bridge-dev-telemetry/batch', (request, response) => {
					void handleBridgeDevTelemetryBatchRequest({
						request,
						response,
						telemetrySink,
					});
				});
				server.middlewares.use('/__bridge-dev-telemetry/status', (request, response) => {
					handleBridgeDevTelemetryStatusRequest({
						request,
						response,
						telemetrySink,
					});
				});
			},
		},
	],
	server: {
		host: '127.0.0.1',
	},
	build: {
		outDir: '../Sources/AgentStudio/Resources/BridgeWeb/app',
		emptyOutDir: true,
		sourcemap: false,
	},
});

const bridgeDevTelemetryMaxBodyBytes = 256 * 1024;

async function handleBridgeDevTelemetryBatchRequest(props: {
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
	readonly telemetrySink: BridgeDevTelemetrySink;
}): Promise<void> {
	if (props.request.method !== 'POST') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	try {
		const body = await readJsonRequestBody(props.request, bridgeDevTelemetryMaxBodyBytes);
		const accepted = await props.telemetrySink.ingest(body);
		writeJsonResponse(props.response, 202, {
			accepted,
			snapshot: props.telemetrySink.snapshot(),
		});
	} catch (error: unknown) {
		writeJsonResponse(props.response, 400, {
			error: error instanceof Error ? error.message : 'invalid_telemetry_request',
			snapshot: props.telemetrySink.snapshot(),
		});
	}
}

function handleBridgeDevTelemetryStatusRequest(props: {
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
	readonly telemetrySink: BridgeDevTelemetrySink;
}): void {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	writeJsonResponse(props.response, 200, props.telemetrySink.snapshot());
}

async function handleBridgeWorktreeSurfaceRequest(props: {
	readonly getProvider: (requestUrl: string | null) => BridgeWorktreeDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	try {
		const provider = await props.getProvider(props.request.url ?? null);
		const surface = await provider.loadWorktreeFileSurface();
		props.response.setHeader('Content-Type', 'application/json; charset=utf-8');
		props.response.end(JSON.stringify(surface));
	} catch (error: unknown) {
		props.response.statusCode = 500;
		props.response.end(
			error instanceof Error ? error.message : 'Bridge worktree surface provider failed',
		);
	}
}

async function handleBridgeWorktreeFileDescriptorRequest(props: {
	readonly getProvider: (requestUrl: string | null) => BridgeWorktreeDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	const requestUrl = props.request.url ?? null;
	const descriptorRequest = parseBridgeWorktreeFileDescriptorRequest({ requestUrl });
	if (descriptorRequest === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree file descriptor request');
		return;
	}
	try {
		const provider = await props.getProvider(requestUrl);
		const descriptorFrame = await provider.loadWorktreeFileDescriptor(descriptorRequest);
		writeJsonResponse(props.response, 200, { frame: descriptorFrame });
	} catch (error: unknown) {
		props.response.statusCode = 404;
		props.response.end(
			error instanceof Error ? error.message : 'Bridge worktree file descriptor missing',
		);
	}
}

async function handleBridgeWorktreeFileContentRequest(props: {
	readonly getProvider: (requestUrl: string | null) => BridgeWorktreeDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
	readonly telemetrySink: BridgeDevTelemetrySink;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	const requestStartedAtMilliseconds = performance.now();
	const requestUrl = props.request.url ?? null;
	const contentUrl = new URL(requestUrl ?? '/', 'http://127.0.0.1');
	const descriptorId = decodeBridgeWorktreeContentHandle(contentUrl.pathname);
	if (descriptorId === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree file content descriptor');
		return;
	}
	const contentRequest = parseBridgeWorktreeFileContentRequest({
		contentUrl,
		descriptorId,
	});
	if (contentRequest === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree file content generation or cursor');
		return;
	}
	let getProviderMilliseconds = 0;
	let providerLoadMilliseconds = 0;
	let byteLength = 0;
	let result: 'failed' | 'success' = 'success';
	let resultReason = 'none';
	try {
		const getProviderStartedAtMilliseconds = performance.now();
		const provider = await props.getProvider(requestUrl);
		getProviderMilliseconds = performance.now() - getProviderStartedAtMilliseconds;
		const providerLoadStartedAtMilliseconds = performance.now();
		const content = await provider.loadWorktreeFileContent(contentRequest);
		providerLoadMilliseconds = performance.now() - providerLoadStartedAtMilliseconds;
		byteLength = Buffer.byteLength(content, 'utf8');
		props.response.setHeader('Content-Type', 'text/plain; charset=utf-8');
		props.response.end(content);
	} catch (error: unknown) {
		result = 'failed';
		resultReason = 'content_unavailable';
		props.response.statusCode = 404;
		props.response.end(
			error instanceof Error ? error.message : 'Bridge worktree file content missing',
		);
	} finally {
		void props.telemetrySink.ingest(
			buildBridgeDevContentResponseTelemetryBatch({
				byteLength,
				getProviderMilliseconds,
				providerLoadMilliseconds,
				responseTotalMilliseconds: performance.now() - requestStartedAtMilliseconds,
				result,
				resultReason,
				scenario: bridgeDevWorktreeContentTelemetryScenario(contentUrl),
				viewer: 'file',
			}),
		);
	}
}

async function handleBridgeWorktreeReviewMetadataRequest(props: {
	readonly getReviewProvider: (requestUrl: string | null) => BridgeWorktreeReviewDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	try {
		const provider = await props.getReviewProvider(props.request.url ?? null);
		if (bridgeWorktreeReviewMetadataFrameRequested(props.request.url ?? null)) {
			const metadataResult = await provider.loadReviewMetadata({ forceRefresh: true });
			writeJsonResponse(props.response, 200, {
				protocolFrame: metadataResult.metadataFrame,
				nextWindowCursor: metadataResult.metadataWindowFrames.length === 0 ? null : '0',
			});
			return;
		}
		const windowCursor = bridgeWorktreeReviewMetadataWindowCursor(props.request.url ?? null);
		if (windowCursor !== null) {
			const metadataResult = await provider.loadReviewMetadata();
			const protocolFrame = metadataResult.metadataWindowFrames[windowCursor] ?? null;
			if (protocolFrame === null) {
				props.response.statusCode = 404;
				props.response.end('Bridge worktree review metadata window missing');
				return;
			}
			writeJsonResponse(props.response, 200, {
				protocolFrame,
				nextWindowCursor:
					windowCursor + 1 >= metadataResult.metadataWindowFrames.length
						? null
						: String(windowCursor + 1),
			});
			return;
		}
		props.response.statusCode = 400;
		props.response.end(
			'Bridge worktree review metadata route requires frame=review-metadata-snapshot or frame=review-metadata-window',
		);
	} catch (error: unknown) {
		props.response.statusCode = 500;
		props.response.end(
			error instanceof Error ? error.message : 'Bridge worktree review metadata failed',
		);
	}
}

function bridgeWorktreeReviewMetadataFrameRequested(requestUrl: string | null): boolean {
	if (requestUrl === null) {
		return false;
	}
	const parsedUrl = new URL(requestUrl, 'http://127.0.0.1');
	return parsedUrl.searchParams.get('frame') === 'review-metadata-snapshot';
}

function bridgeWorktreeReviewMetadataWindowCursor(requestUrl: string | null): number | null {
	if (requestUrl === null) {
		return null;
	}
	const parsedUrl = new URL(requestUrl, 'http://127.0.0.1');
	if (parsedUrl.searchParams.get('frame') !== 'review-metadata-window') {
		return null;
	}
	const rawCursor = parsedUrl.searchParams.get('cursor');
	if (rawCursor === null || !/^\d+$/u.test(rawCursor)) {
		return null;
	}
	return Number(rawCursor);
}

export function bridgeWorktreeDevProviderConfigCacheKey(props: {
	readonly env: Readonly<Record<string, string | undefined>>;
	readonly requestUrl: string | null;
}): string | null {
	const contentUrl = new URL(props.requestUrl ?? '/', 'http://127.0.0.1');
	if (
		props.requestUrl?.includes('://') === true &&
		!bridgeWorktreeDevProviderCacheHostnameIsLoopback(contentUrl.hostname)
	) {
		return null;
	}
	if (
		contentUrl.searchParams.has('worktree') ||
		contentUrl.searchParams.has('repo') ||
		contentUrl.searchParams.has('base')
	) {
		return null;
	}
	const scenario =
		singleSearchParamValue(contentUrl, 'scenario') ??
		props.env['BRIDGE_WEB_DEV_SCENARIO'] ??
		'current-worktree';
	const envWorktree = props.env['BRIDGE_WEB_DEV_WORKTREE'] ?? 'package-root';
	const envBase = props.env['BRIDGE_WEB_DEV_BASE'] ?? 'default-base';
	return [scenario, envWorktree, envBase].join('\u0000');
}

function bridgeWorktreeDevProviderCacheHostnameIsLoopback(hostname: string): boolean {
	return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '[::1]';
}

async function handleBridgeWorktreeReviewContentRequest(props: {
	readonly getReviewProvider: (requestUrl: string | null) => BridgeWorktreeReviewDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
	readonly telemetrySink: BridgeDevTelemetrySink;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	const requestStartedAtMilliseconds = performance.now();
	const requestUrl = props.request.url ?? null;
	const contentUrl = new URL(requestUrl ?? '/', 'http://127.0.0.1');
	const handleId = decodeBridgeWorktreeContentHandle(contentUrl.pathname);
	if (handleId === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree review content handle');
		return;
	}
	if (
		!hasOnlySearchParams(contentUrl, {
			allowedNames: ['cursor', 'generation', 'revision', 'scenario'],
			requiredNames: ['cursor', 'generation', 'revision'],
		})
	) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree review content query');
		return;
	}
	const contentRequest = parseBridgeWorktreeReviewContentRequest({
		contentUrl,
		handleId,
	});
	if (contentRequest === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree review content identity');
		return;
	}
	let getProviderMilliseconds = 0;
	let providerLoadMilliseconds = 0;
	let byteLength = 0;
	let result: 'failed' | 'success' = 'success';
	let resultReason = 'none';
	try {
		const getProviderStartedAtMilliseconds = performance.now();
		const provider = await props.getReviewProvider(requestUrl);
		getProviderMilliseconds = performance.now() - getProviderStartedAtMilliseconds;
		const providerLoadStartedAtMilliseconds = performance.now();
		const content = await provider.loadReviewContent(contentRequest);
		providerLoadMilliseconds = performance.now() - providerLoadStartedAtMilliseconds;
		byteLength = Buffer.byteLength(content, 'utf8');
		props.response.setHeader('Cache-Control', 'no-store');
		props.response.setHeader('Content-Type', 'text/plain; charset=utf-8');
		props.response.end(content);
	} catch (error: unknown) {
		result = 'failed';
		resultReason = 'content_unavailable';
		props.response.statusCode = 404;
		props.response.end(
			error instanceof Error ? error.message : 'Bridge worktree review content missing',
		);
	} finally {
		void props.telemetrySink.ingest(
			buildBridgeDevContentResponseTelemetryBatch({
				byteLength,
				getProviderMilliseconds,
				providerLoadMilliseconds,
				responseTotalMilliseconds: performance.now() - requestStartedAtMilliseconds,
				result,
				resultReason,
				scenario: bridgeDevWorktreeContentTelemetryScenario(contentUrl),
				viewer: 'review',
			}),
		);
	}
}

function parseBridgeWorktreeReviewContentRequest(props: {
	readonly contentUrl: URL;
	readonly handleId: string;
}): BridgeWorktreeReviewContentRequest | null {
	const generation = parseNonnegativeIntegerSearchParam(props.contentUrl, 'generation');
	const revision = parseNonnegativeIntegerSearchParam(props.contentUrl, 'revision');
	const packageId = singleSearchParamValue(props.contentUrl, 'cursor');
	if (generation === null || revision === null || packageId === null || packageId.length === 0) {
		return null;
	}
	return {
		generation,
		handleId: props.handleId,
		packageId,
		revision,
	};
}

export function parseBridgeWorktreeFileDescriptorRequest(props: {
	readonly requestUrl: string | null;
}): BridgeWorktreeDevProviderWorktreeFileDescriptorRequest | null {
	const descriptorUrl = new URL(props.requestUrl ?? '/', 'http://127.0.0.1');
	if (
		!hasOnlySearchParams(descriptorUrl, {
			allowedNames: ['cursor', 'generation', 'path', 'scenario'],
			requiredNames: ['cursor', 'generation', 'path'],
		})
	) {
		return null;
	}
	const path = singleSearchParamValue(descriptorUrl, 'path');
	const subscriptionGeneration = parseNonnegativeIntegerSearchParam(descriptorUrl, 'generation');
	const sourceCursor = singleSearchParamValue(descriptorUrl, 'cursor');
	if (
		path === null ||
		path.length === 0 ||
		subscriptionGeneration === null ||
		sourceCursor === null ||
		sourceCursor.length === 0
	) {
		return null;
	}
	return {
		path,
		sourceCursor,
		subscriptionGeneration,
	};
}

export function parseBridgeWorktreeFileContentRequest(props: {
	readonly contentUrl: URL;
	readonly descriptorId: string;
}): BridgeWorktreeDevProviderWorktreeFileContentRequest | null {
	if (
		!hasOnlySearchParams(props.contentUrl, {
			allowedNames: ['cursor', 'generation', 'scenario'],
			requiredNames: ['cursor', 'generation'],
		})
	) {
		return null;
	}
	const subscriptionGeneration = parseNonnegativeIntegerSearchParam(props.contentUrl, 'generation');
	const sourceCursor = singleSearchParamValue(props.contentUrl, 'cursor');
	if (subscriptionGeneration === null || sourceCursor === null || sourceCursor.length === 0) {
		return null;
	}
	return {
		descriptorId: props.descriptorId,
		sourceCursor,
		subscriptionGeneration,
	};
}

export function decodeBridgeWorktreeContentHandle(pathname: string): string | null {
	try {
		const handleId = decodeURIComponent(pathname.replace(/^\//u, ''));
		return handleId.length === 0 || handleId.includes('/') ? null : handleId;
	} catch {
		return null;
	}
}

function bridgeDevWorktreeContentTelemetryScenario(contentUrl: URL): string {
	const scenario = singleSearchParamValue(contentUrl, 'scenario') ?? 'default';
	return `vite-dev-worktree-${scenario}`;
}

function singleSearchParamValue(url: URL, name: string): string | null {
	const values = url.searchParams.getAll(name);
	return values.length === 1 ? (values[0] ?? null) : null;
}

async function readJsonRequestBody(request: IncomingMessage, maxBytes: number): Promise<unknown> {
	let byteCount = 0;
	const chunks: Buffer[] = [];
	for await (const chunk of request) {
		const buffer = typeof chunk === 'string' ? Buffer.from(chunk) : chunk;
		byteCount += buffer.byteLength;
		if (byteCount > maxBytes) {
			throw new Error('telemetry_request_too_large');
		}
		chunks.push(buffer);
	}
	try {
		const parsedJson: unknown = JSON.parse(Buffer.concat(chunks).toString('utf8'));
		return parsedJson;
	} catch {
		throw new Error('invalid_telemetry_json');
	}
}

function writeJsonResponse(
	response: ServerResponse,
	statusCode: number,
	body: BridgeDevTelemetrySnapshot | Readonly<Record<string, unknown>>,
): void {
	response.statusCode = statusCode;
	response.setHeader('Content-Type', 'application/json; charset=utf-8');
	response.end(JSON.stringify(body));
}

function parseNonnegativeIntegerSearchParam(url: URL, name: string): number | null {
	const values = url.searchParams.getAll(name);
	const value = values.length === 1 ? values[0] : null;
	if (value === null || value === undefined || !/^(?:0|[1-9]\d*)$/u.test(value)) {
		return null;
	}
	const parsedValue = Number(value);
	return Number.isSafeInteger(parsedValue) ? parsedValue : null;
}

function hasOnlySearchParams(
	url: URL,
	props: {
		readonly allowedNames: readonly string[];
		readonly requiredNames: readonly string[];
	},
): boolean {
	const allowed = new Set(props.allowedNames);
	for (const [name] of url.searchParams.entries()) {
		if (!allowed.has(name)) {
			return false;
		}
	}
	return props.requiredNames.every(
		(name: string): boolean => url.searchParams.getAll(name).length === 1,
	);
}
