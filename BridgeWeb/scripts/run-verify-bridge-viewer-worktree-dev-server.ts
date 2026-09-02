import { createServer as createViteServer } from 'vite';

const moduleLoader = await createViteServer({
	configFile: false,
	optimizeDeps: { noDiscovery: true },
	server: { hmr: false, middlewareMode: true },
});

try {
	await moduleLoader.ssrLoadModule('/scripts/verify-bridge-viewer-worktree-dev-server.ts');
} finally {
	await moduleLoader.close();
}
