import { useRef, type MutableRefObject } from 'react';

export interface BridgeCodeViewInitialSelection {
	readonly selectedItemId: string | null;
	readonly sourceKey: string;
}

export function useBridgeCodeViewInitialSelection(props: {
	readonly selectedItemId: string | null;
	readonly sourceKey: string;
}): MutableRefObject<BridgeCodeViewInitialSelection | null> {
	const initialSelectionRef = useRef<BridgeCodeViewInitialSelection | null>(null);
	if (initialSelectionRef.current?.sourceKey !== props.sourceKey) {
		initialSelectionRef.current = props;
	}
	return initialSelectionRef;
}
