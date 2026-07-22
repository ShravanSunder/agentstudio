import type { BridgeReviewItemDescriptor } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';

export function makeHydratedWorkerPreparedCodeViewFileItem(props: {
	readonly cacheKey: string;
	readonly contentRoles: BridgeCodeViewItem['bridgeMetadata']['contentRoles'];
	readonly contents?: string;
	readonly item: BridgeReviewItemDescriptor;
}): BridgeCodeViewItem {
	const contents = props.contents ?? '';
	const displayPath = props.item.headPath ?? props.item.basePath ?? props.item.itemId;
	return {
		id: props.item.itemId,
		type: 'file',
		file: {
			name: displayPath,
			contents,
			cacheKey: props.cacheKey,
			...(props.item.language === null || props.item.language === undefined
				? {}
				: { lang: props.item.language }),
		},
		version: props.item.itemVersion * 3 + 2,
		bridgeMetadata: {
			itemId: props.item.itemId,
			displayPath,
			contentState: 'hydrated',
			contentRoles: props.contentRoles,
			cacheKey: props.cacheKey,
			lineCount: contents === '' ? 0 : contents.split('\n').length - 1,
		},
	};
}
