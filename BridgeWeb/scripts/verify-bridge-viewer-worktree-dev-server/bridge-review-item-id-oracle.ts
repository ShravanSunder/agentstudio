import { createHash } from 'node:crypto';

const bridgeDirectGitDiffFileIdHashDomain = 'agentstudio-bridge-direct-git-diff-file-id-v1';
const bridgeReviewItemIdPrefixByteCount = Buffer.byteLength('item-');
const bridgeMaximumIdentifierByteLength = 128;
const bridgeMaximumFileIdByteLength =
	bridgeMaximumIdentifierByteLength - bridgeReviewItemIdPrefixByteCount;
const bridgeAllowedFileIdPattern = /^[A-Za-z0-9._:-]+$/u;

export function bridgeReviewItemIdOracle(props: {
	readonly newContentHash: string | null;
	readonly oldContentHash: string | null;
	readonly path: string;
	readonly previousPath: string | null;
}): string {
	const sourceFileId = [
		'gitdiff',
		props.previousPath ?? 'none',
		props.path,
		props.oldContentHash ?? 'none',
		props.newContentHash ?? 'none',
	].join(':');
	const fileId =
		sourceFileId.length > 0 &&
		Buffer.byteLength(sourceFileId) <= bridgeMaximumFileIdByteLength &&
		bridgeAllowedFileIdPattern.test(sourceFileId)
			? sourceFileId
			: `git-diff-${createHash('sha256')
					.update(`${bridgeDirectGitDiffFileIdHashDomain}:${sourceFileId}`)
					.digest('hex')}`;
	return `item-${fileId}`;
}
