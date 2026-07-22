import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
} from '../../foundation/review-package/bridge-review-package.js';

export function bridgeCodeViewDescriptorPlaceholderSignature(
	item: BridgeReviewItemDescriptor | undefined,
): string {
	if (item === undefined) {
		return 'missing';
	}
	const lineCounts = item.contentLineCountsByRole;
	return [
		item.itemId,
		item.itemKind,
		item.changeKind,
		item.basePath ?? '',
		item.headPath ?? '',
		String(item.additions),
		String(item.deletions),
		contentHandlePresence(item.contentRoles.base),
		contentHandlePresence(item.contentRoles.diff),
		contentHandlePresence(item.contentRoles.file),
		contentHandlePresence(item.contentRoles.head),
		String(lineCounts?.base ?? ''),
		String(lineCounts?.diff ?? ''),
		String(lineCounts?.file ?? ''),
		String(lineCounts?.head ?? ''),
	].join('\u001f');
}

function contentHandlePresence(handle: BridgeContentHandle | null | undefined): string {
	return handle === null || handle === undefined ? 'none' : handle.role;
}
