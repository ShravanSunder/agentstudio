import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { withBridgeWebAppBuildLock } from './build-app-assets-lock.ts';

const packageRootPath = fileURLToPath(new URL('../', import.meta.url));

await withBridgeWebAppBuildLock(async (): Promise<void> => {
	await runCommand({ command: 'tsc', args: ['--noEmit'], cwd: packageRootPath });
	await runCommand({
		command: 'node',
		args: ['--experimental-strip-types', 'scripts/build-app-assets.ts'],
		cwd: packageRootPath,
		env: { ...process.env, BRIDGE_WEB_APP_BUILD_LOCK_HELD: '1' },
	});
	await runCommand({
		command: 'node',
		args: ['--experimental-strip-types', 'scripts/normalize-build-output.ts'],
		cwd: packageRootPath,
	});
	await runCommand({
		command: 'pnpm',
		args: ['run', 'audit:assets'],
		cwd: packageRootPath,
	});
});

async function runCommand(props: {
	readonly command: string;
	readonly args: readonly string[];
	readonly cwd: string;
	readonly env?: NodeJS.ProcessEnv;
}): Promise<void> {
	await new Promise<void>((resolve, reject) => {
		const child = spawn(props.command, props.args, {
			cwd: props.cwd,
			env: props.env,
			stdio: 'inherit',
		});

		child.on('error', reject);
		child.on('exit', (code: number | null): void => {
			if (code === 0) {
				resolve();
				return;
			}

			reject(new Error(`${props.command} exited with ${code ?? 'unknown status'}`));
		});
	});
}
