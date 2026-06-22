import type { Dirent } from 'node:fs';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { extname } from 'node:path';

const buildOutputDirectory = new URL(
	'../../Sources/AgentStudio/Resources/BridgeWeb/app/',
	import.meta.url,
);
const normalizedExtensions = new Set(['.css', '.html', '.js', '.json', '.map', '.svg']);

async function normalizeBuildOutputDirectory(directoryUrl: URL): Promise<void> {
	const entries = await readdir(directoryUrl, { withFileTypes: true });

	await Promise.all(
		entries.map((entry: Dirent): Promise<void> => normalizeBuildOutputEntry(directoryUrl, entry)),
	);
}

async function normalizeBuildOutputEntry(directoryUrl: URL, entry: Dirent): Promise<void> {
	const entryUrl = new URL(`${entry.name}${entry.isDirectory() ? '/' : ''}`, directoryUrl);

	if (entry.isDirectory()) {
		await normalizeBuildOutputDirectory(entryUrl);
		return;
	}

	if (!entry.isFile() || !normalizedExtensions.has(extname(entry.name))) {
		return;
	}

	const content = await readFile(entryUrl, 'utf8');
	const normalizedContent = content.replace(/[ \t]+$/gm, '');

	if (normalizedContent !== content) {
		await writeFile(entryUrl, normalizedContent, 'utf8');
	}
}

await normalizeBuildOutputDirectory(buildOutputDirectory);
