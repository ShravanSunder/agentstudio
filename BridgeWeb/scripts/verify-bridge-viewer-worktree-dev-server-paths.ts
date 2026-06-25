import { realpath } from 'node:fs/promises';
import { isAbsolute, relative, resolve, sep } from 'node:path';

export async function resolveBridgeWorktreeVerifierWritePath(props: {
	readonly descriptorPath: string;
	readonly rootPath: string;
}): Promise<string> {
	if (isAbsolute(props.descriptorPath)) {
		throw new Error(`Bridge worktree verifier path must be relative: ${props.descriptorPath}`);
	}
	const lexicalPath = resolve(props.rootPath, props.descriptorPath);
	if (!isPathInsideRoot({ absolutePath: lexicalPath, rootPath: props.rootPath })) {
		throw new Error(`Bridge worktree verifier path escapes root: ${props.descriptorPath}`);
	}
	const realRootPath = await realpath(props.rootPath);
	const realAbsolutePath = await realpath(lexicalPath);
	if (!isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: realRootPath })) {
		throw new Error(`Bridge worktree verifier path escapes root: ${props.descriptorPath}`);
	}
	return realAbsolutePath;
}

function isPathInsideRoot(props: {
	readonly absolutePath: string;
	readonly rootPath: string;
}): boolean {
	const relativePath = relative(props.rootPath, props.absolutePath);
	return (
		relativePath.length > 0 &&
		!relativePath.startsWith('..') &&
		!relativePath.split(sep).includes('..')
	);
}
