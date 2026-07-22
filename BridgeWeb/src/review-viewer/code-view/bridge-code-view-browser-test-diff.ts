import {
	parseDiffFromFile,
	type CreatePatchOptionsNonabortable,
	type FileContents,
	type FileDiffMetadata,
} from '@pierre/diffs';

export function parseBridgeCodeViewDiffForBrowserTest(
	oldFile: FileContents,
	newFile: FileContents,
	options?: CreatePatchOptionsNonabortable,
	throwOnError?: boolean,
): FileDiffMetadata {
	return parseDiffFromFile(oldFile, newFile, options, throwOnError);
}
