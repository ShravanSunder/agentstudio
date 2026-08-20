#!/usr/bin/env bash
set -euo pipefail

# Normalize arbitrary test payload bytes before mise/xcbeautify consume the
# stream, then filter known, non-actionable Ghostty linker noise while
# preserving all other diagnostics.
/usr/bin/iconv -f UTF-8 -t UTF-8 -c | awk '
{
    if (index($0, "libghostty-fat.a(ext.o)") &&
        (index($0, "_ImFontConfig_ImFontConfig") || index($0, "_ImGuiStyle_ImGuiStyle")))
    {
        next
    }
    print
}
'
