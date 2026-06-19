import type { IncomingMessage, ServerResponse } from 'node:http';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

import {
	createBridgeWorktreeDevProvider,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProvider,
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
				const providerPromisesByConfig = new Map<string, BridgeWorktreeDevProviderPromise>();
				const getProvider = async (requestUrl: string | null): BridgeWorktreeDevProviderPromise => {
					const config = await resolveBridgeWorktreeDevProviderConfig({
						env: process.env,
						packageRoot: bridgeWebPackageRoot,
						requestUrl,
					});
					const configKey = `${config.worktreeRoot}\u0000${config.baseRef}`;
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
	const handleId = decodeURIComponent(contentUrl.pathname.replace(/^\//u, ''));
	if (handleId.length === 0 || handleId.includes('/')) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree content handle');
		return;
	}
	try {
		const provider = await props.getProvider(requestUrl);
		const content = await provider.loadContent(handleId);
		props.response.setHeader('Content-Type', 'text/plain; charset=utf-8');
		props.response.end(content);
	} catch (error: unknown) {
		props.response.statusCode = 404;
		props.response.end(error instanceof Error ? error.message : 'Bridge worktree content missing');
	}
}
