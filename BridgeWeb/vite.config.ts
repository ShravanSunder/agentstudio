import { Buffer } from 'node:buffer';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

import {
	createBridgeDevTelemetrySink,
	type BridgeDevTelemetrySink,
	type BridgeDevTelemetrySnapshot,
} from './scripts/dev-server/bridge-dev-telemetry.js';
import { createBridgeProductDevCarrier } from './scripts/dev-server/bridge-product-dev-carrier.js';
import {
	createBridgeWorktreeDevProvider,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProvider,
	type BridgeWorktreeDevProviderConfig,
} from './scripts/dev-server/bridge-worktree-dev-provider.js';
import { BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE } from './src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_CONTENT_ROUTE,
	BRIDGE_PRODUCT_STREAM_ROUTE,
} from './src/core/comm-worker/bridge-product-dev-routes.js';

type BridgeWorktreeDevProviderPromise = Promise<BridgeWorktreeDevProvider>;

const bridgeWebPackageRoot = dirname(fileURLToPath(import.meta.url));
const bridgeProductDevRoutesPath = `${bridgeWebPackageRoot}/src/core/comm-worker/bridge-product-dev-routes.ts`;

export default defineConfig({
	base: './',
	resolve: {
		alias: [
			{
				find: './bridge-product-routes.js',
				replacement: bridgeProductDevRoutesPath,
			},
			{ find: '@', replacement: `${bridgeWebPackageRoot}/src` },
		],
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
				const productCarrier = createBridgeProductDevCarrier({
					getFileProvider: getProvider,
					getReviewSourceConfig: getProviderConfig,
				});
				server.middlewares.use(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE, (request, response) => {
					void productCarrier.handleBootstrapRequest({ request, response });
				});
				server.middlewares.use(BRIDGE_PRODUCT_COMMAND_ROUTE, (request, response) => {
					void productCarrier.handleCommandRequest({ request, response });
				});
				server.middlewares.use(BRIDGE_PRODUCT_STREAM_ROUTE, (request, response) => {
					void productCarrier.handleStreamRequest({ request, response });
				});
				server.middlewares.use(BRIDGE_PRODUCT_CONTENT_ROUTE, (request, response) => {
					void productCarrier.handleContentRequest({ request, response });
				});
				server.httpServer?.once('close', (): void => productCarrier.dispose());
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
const bridgeDevTelemetryCapability = 'dev-telemetry-capability-0123456789abcdef';

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
	if (
		props.request.headers['x-agentstudio-bridge-telemetry-capability'] !==
		bridgeDevTelemetryCapability
	) {
		writeJsonResponse(props.response, 401, { error: 'unauthorized' });
		return;
	}
	try {
		const body = await readJsonRequestBody(props.request, bridgeDevTelemetryMaxBodyBytes);
		const admission = await props.telemetrySink.ingestWorkerBatch(body);
		writeJsonResponse(props.response, bridgeTelemetryAdmissionStatusCode(admission), admission);
	} catch (error: unknown) {
		writeJsonResponse(props.response, 400, {
			error: error instanceof Error ? error.message : 'invalid_telemetry_request',
			snapshot: props.telemetrySink.snapshot(),
		});
	}
}

function bridgeTelemetryAdmissionStatusCode(
	admission: Awaited<ReturnType<BridgeDevTelemetrySink['ingestWorkerBatch']>>,
): number {
	if (admission.type === 'accepted' || admission.type === 'accepted_with_loss') {
		return 202;
	}
	if (admission.type === 'duplicate') {
		return 200;
	}
	if (admission.reason === 'unavailable') {
		return 503;
	}
	return admission.reason === 'invalid_body' ? 400 : 409;
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
