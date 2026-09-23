interface BridgeFileViewerContentHeaderTitleProps {
	readonly selectedDocumentLocation: string | null;
	readonly selectedPath: string | null;
	readonly sourceId: string;
}

/**
 * An individually opened document is titled by its real location, never by the
 * synthetic collection group path it is listed under.
 */
export function bridgeFileViewerContentHeaderTitle({
	selectedDocumentLocation,
	selectedPath,
}: BridgeFileViewerContentHeaderTitleProps): string {
	return selectedDocumentLocation ?? selectedPath ?? 'Source pending';
}
