export interface ReviewWitnessTreeFile {
	readonly itemId: string;
	readonly path: string;
}

export interface ReviewWitnessTreeRow {
	readonly depth: number;
	readonly isDirectory: boolean;
	readonly itemId: string | null;
	readonly path: string;
	readonly rowId: string;
}

export function reviewWitnessTreeRows(
	files: readonly ReviewWitnessTreeFile[],
): readonly ReviewWitnessTreeRow[] {
	const rows: ReviewWitnessTreeRow[] = [
		{ depth: 0, isDirectory: true, itemId: null, path: 'Sources', rowId: 'dir-sources' },
	];
	let previousDirectory = '';
	for (const file of files) {
		const directory = file.path.slice(0, file.path.lastIndexOf('/'));
		if (directory !== previousDirectory) {
			rows.push({
				depth: 1,
				isDirectory: true,
				itemId: null,
				path: directory,
				rowId: `dir-${directory.replaceAll('/', '-').toLowerCase()}`,
			});
			previousDirectory = directory;
		}
		rows.push({
			depth: 2,
			isDirectory: false,
			itemId: file.itemId,
			path: file.path,
			rowId: `row-${file.itemId}`,
		});
	}
	return rows;
}
