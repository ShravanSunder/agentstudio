import type { IncomingMessage, ServerResponse } from 'node:http';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

import {
	createBridgeWorktreeDevProvider,
	type BridgeWorktreeDevProvider,
} from './scripts/dev-server/bridge-worktree-dev-provider.js';

type BridgeWorktreeDevProviderPromise = Promise<BridgeWorktreeDevProvider>;

export default defineConfig({
	base: './',
	plugins: [
		react(),
		{
			name: 'bridge-worktree-dev-provider',
			configureServer(server) {
				const configuredWorktreeRoot = process.env['BRIDGE_WEB_DEV_WORKTREE'];
				if (configuredWorktreeRoot === undefined || configuredWorktreeRoot.length === 0) {
					return;
				}
				let providerPromise: BridgeWorktreeDevProviderPromise | null = null;
				const getProvider = (): BridgeWorktreeDevProviderPromise => {
					providerPromise ??= createBridgeWorktreeDevProvider({
						baseRef: process.env['BRIDGE_WEB_DEV_BASE'] ?? 'HEAD',
						worktreeRoot: configuredWorktreeRoot,
					});
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
	readonly getProvider: () => BridgeWorktreeDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	try {
		const provider = await props.getProvider();
		const reviewPackage = await provider.loadReviewPackage();
		props.response.setHeader('Content-Type', 'application/json; charset=utf-8');
		props.response.end(JSON.stringify(reviewPackage));
	} catch (error: unknown) {
		props.response.statusCode = 500;
		props.response.end(error instanceof Error ? error.message : 'Bridge worktree provider failed');
	}
}

async function handleBridgeWorktreeContentRequest(props: {
	readonly getProvider: () => BridgeWorktreeDevProviderPromise;
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}): Promise<void> {
	if (props.request.method !== 'GET') {
		props.response.statusCode = 405;
		props.response.end('Method Not Allowed');
		return;
	}
	const handleId = decodeURIComponent(props.request.url?.replace(/^\//u, '') ?? '');
	if (handleId.length === 0 || handleId.includes('/')) {
		props.response.statusCode = 400;
		props.response.end('Invalid Bridge worktree content handle');
		return;
	}
	try {
		const provider = await props.getProvider();
		const content = await provider.loadContent(handleId);
		props.response.setHeader('Content-Type', 'text/plain; charset=utf-8');
		props.response.end(content);
	} catch (error: unknown) {
		props.response.statusCode = 404;
		props.response.end(error instanceof Error ? error.message : 'Bridge worktree content missing');
	}
}
