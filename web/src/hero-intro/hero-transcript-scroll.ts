/** Align a transcript's clipping edge with a row boundary after playback or a direct seek. */
export function snapHeroTranscriptToWholeRow(transcript: HTMLElement): void {
  const transcriptTop = transcript.getBoundingClientRect().top;
  const visibleRow = (row: HTMLElement): boolean => {
    if (row.getClientRects().length === 0) return false;
    for (
      let element: Element | null = row;
      element !== null && element !== transcript;
      element = element.parentElement
    ) {
      if (Number(getComputedStyle(element).opacity) < 0.05) return false;
    }
    return true;
  };
  const partial = [
    ...transcript.querySelectorAll<HTMLElement>(
      ".hero-claude-startup, .hero-codex-startup, .hero-transcript-row",
    ),
  ]
    .filter(visibleRow)
    .filter((row) => {
      const bounds = row.getBoundingClientRect();
      return bounds.top < transcriptTop - 0.5 && bounds.bottom > transcriptTop + 0.5;
    })
    .sort(
      (left, right) => left.getBoundingClientRect().bottom - right.getBoundingClientRect().bottom,
    )[0];
  if (partial === undefined) return;
  const bounds = partial.getBoundingClientRect();
  const scrollBefore = transcript.scrollTop;
  transcript.scrollTop += bounds.bottom - transcriptTop + 0.5;
  if (transcript.scrollTop <= scrollBefore + 0.5) {
    // At the scroll limit, show this row from its start; bottom padding preserves the result.
    transcript.scrollTop = scrollBefore + bounds.top - transcriptTop;
  }
}
