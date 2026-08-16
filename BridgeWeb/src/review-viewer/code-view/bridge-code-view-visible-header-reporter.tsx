import { useLayoutEffect } from 'react';

export function BridgeCodeViewVisibleHeaderReporter(props: {
	readonly itemId: string;
	readonly onHeaderVisibilityChange: (itemId: string, isVisible: boolean) => void;
}): null {
	const { itemId, onHeaderVisibilityChange } = props;
	useLayoutEffect((): (() => void) => {
		onHeaderVisibilityChange(itemId, true);
		return (): void => {
			onHeaderVisibilityChange(itemId, false);
		};
	}, [itemId, onHeaderVisibilityChange]);
	return null;
}
