#!/usr/bin/env bash
set -euo pipefail

# Filter known, non-actionable linker noise from Ghostty vendor artifacts while
# preserving all other compiler/linker diagnostics.
awk '
{
    if (index($0, "libghostty-fat.a(ext.o)") &&
        (index($0, "_ImFontConfig_ImFontConfig") || index($0, "_ImGuiStyle_ImGuiStyle")))
    {
        next
    }
    print
}
'
