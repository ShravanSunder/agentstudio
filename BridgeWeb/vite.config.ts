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
import {
	createBridgeWorktreeDevProvider,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProvider,
	type BridgeWorktreeDevProviderContentRequest,
} from './scripts/dev-server/bridge-worktree-dev-provider.js';

type BridgeWorktreeDevProviderPromise = Promise<BridgeWorktreeDevProvider>;

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
				const getProvider = async (requestUrl: string | null): BridgeWorktreeDevProviderPromise => {
					const config = await resolveBridgeWorktreeDevProviderConfig({
						env: process.env,
						packageRoot: bridgeWebPackageRoot,
						requestUrl,
					});
					const configKey = `${config.scenarioName}\u0000${config.worktreeRoot}\u0000${config.baseRef}`;
					const existingProviderPromise = providerPromisesByConfig.get(configKey);
					if (existingProviderPromise !== undefined) {
						return existingProviderPromise;
					}
					const providerPromise = createBridgeWorktreeDevProvider(config);
					providerPromisesByConfig.set(configKey, providerPromise);
					return providerPromise;
				};
				server.middlewares.use('/__bridge-worktree/package', (request, response) => {
					void handleBridgeWorktreePackageRequest({ getProvider, request, response });
				});
				server.middlewares.use('/__bridge-worktree/content', (request, response) => {
					void handleBridgeWorktreeContentRequest({ getProvider, request, response });
				});
				server.middlewares.use('/__bridge-dev-telemetry/batch', (request, response) => {
					void handleBridgeDevTelemetryBatchRequest({ request, response, telemetrySink });
				});
				server.middlewares.use('/__bridge-dev-telemetry/status', (request, response) => {
					handleBridgeDevTelemetryStatusRequest({ request, response, telemetrySink });
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

async function handleBridgeWorktreePackageRequest(props: {
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
		const reviewPackage = await provider.loadReviewPackage();
		props.response.setHeader('Content-Type', 'application/json; charset=utf-8');
		props.response.end(JSON.stringify(reviewPackage));
	} catch (error: unknown) {
		props.response.statusCode = 500;
		props.response.end(error instanceof Error ? error.message : 'Bridge worktree provider failed');
	}
}

async function handleBridgeWorktreeContentRequest(props: {
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
	const contentUrl = new URL(requestUrl ?? '/', 'http://127.0.0.1');
	const handleId = decodeBridgeWorktreeContentHandle(contentUrl.pathname);
	if (handleId === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree content handle');
		return;
	}
	const contentRequest = parseBridgeWorktreeContentRequest({ contentUrl, handleId });
	if (contentRequest === null) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree content generation or revision');
		return;
	}
	try {
		const provider = await props.getProvider(requestUrl);
		const content = await provider.loadContent(contentRequest);
		props.response.setHeader('Content-Type', 'text/plain; charset=utf-8');
		props.response.end(content);
	} catch (error: unknown) {
		props.response.statusCode = 404;
		props.response.end(error instanceof Error ? error.message : 'Bridge worktree content missing');
	}
}

export function parseBridgeWorktreeContentRequest(props: {
	readonly contentUrl: URL;
	readonly handleId: string;
}): BridgeWorktreeDevProviderContentRequest | null {
	if (
		!hasOnlySearchParams(props.contentUrl, {
			allowedNames: ['generation', 'revision', 'scenario'],
			requiredNames: ['generation', 'revision'],
		})
	) {
		return null;
	}
	const reviewGeneration = parseNonnegativeIntegerSearchParam(props.contentUrl, 'generation');
	const revision = parseNonnegativeIntegerSearchParam(props.contentUrl, 'revision');
	if (reviewGeneration === null || revision === null) {
		return null;
	}
	return {
		handleId: props.handleId,
		reviewGeneration,
		revision,
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
		return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
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
