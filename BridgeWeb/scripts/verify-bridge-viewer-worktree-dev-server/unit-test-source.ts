import { readdir, readFile } from 'node:fs/promises';

const verifierMainSourceUrl = new URL(
	'../verify-bridge-viewer-worktree-dev-server.ts',
	import.meta.url,
);
const verifierModuleDirectoryUrl = new URL('./', import.meta.url);

export async function readWorktreeDevServerVerifierSource(): Promise<string> {
	const moduleFileNames = (await readdir(verifierModuleDirectoryUrl))
		.filter(
			(fileName: string): boolean => fileName.endsWith('.ts') && !fileName.startsWith('unit-'),
		)
		.toSorted();
	const sourceUrls = [
		verifierMainSourceUrl,
		...moduleFileNames.map(
			(fileName: string): URL => new URL(fileName, verifierModuleDirectoryUrl),
		),
	];
	const sourceTexts = await Promise.all(
		sourceUrls.map((sourceUrl: URL): Promise<string> => readFile(sourceUrl, 'utf8')),
	);
	return sourceTexts.join('\n');
}
