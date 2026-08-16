export function openedReviewItemAfterSelectionChange(props: {
	readonly openedReviewItemId: string | null;
	readonly selectedItemId: string | null;
}): string | null {
	if (props.selectedItemId === null || props.selectedItemId === props.openedReviewItemId) {
		return props.openedReviewItemId;
	}
	return null;
}

export function openedReviewItemAfterReviewSourceChange(props: {
	readonly currentReviewPackageId: string | null;
	readonly openedReviewItemId: string | null;
	readonly previousReviewPackageId: string | null;
}): string | null {
	if (
		props.currentReviewPackageId === null ||
		props.previousReviewPackageId === null ||
		props.currentReviewPackageId === props.previousReviewPackageId
	) {
		return props.openedReviewItemId;
	}
	return null;
}
