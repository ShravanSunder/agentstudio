#!/usr/bin/env bash
set -euo pipefail

# Computes a content-addressed fingerprint for every input that can affect the
# SwiftPM test bundles. The caller runs this after generated resources and the
# Ghostty framework have been prepared.

PROJECT_ROOT="${SWIFT_BUILD_INPUT_ROOT:-$(git rev-parse --show-toplevel)}"
readonly PROJECT_ROOT

required_inputs=(
    "Package.swift"
    "Package.resolved"
    ".mise.toml"
    "Sources"
    "Tests"
    "Frameworks/GhosttyKit.xcframework"
    "scripts/swift-build-slot.sh"
    "scripts/swift-test-helpers.sh"
    "scripts/run-swift-test-task.sh"
    "scripts/swift-build-input-fingerprint.sh"
)

for relative_path in "${required_inputs[@]}"; do
    if [[ ! -e "$PROJECT_ROOT/$relative_path" && ! -L "$PROJECT_ROOT/$relative_path" ]]; then
        printf 'missing Swift build input: %s\n' "$relative_path" >&2
        exit 1
    fi
done

records_file=$(mktemp "${TMPDIR:-/tmp}/agentstudio-swift-build-inputs.XXXXXX")
trap 'rm -f "$records_file"' EXIT

record_file() {
    local absolute_path="$1"
    local relative_path="${absolute_path#"$PROJECT_ROOT/"}"
    local mode
    mode=$(/usr/bin/stat -f '%Lp' "$absolute_path")
    local content_digest
    content_digest=$(/usr/bin/shasum -a 256 "$absolute_path" | /usr/bin/awk '{ print $1 }')
    printf 'file\t%s\t%s\t%s\n' "$mode" "$relative_path" "$content_digest"
}

record_symlink() {
    local absolute_path="$1"
    local relative_path="${absolute_path#"$PROJECT_ROOT/"}"
    local mode
    mode=$(/usr/bin/stat -f '%Lp' "$absolute_path")
    printf 'symlink\t%s\t%s\t%s\n' "$mode" "$relative_path" "$(/usr/bin/readlink "$absolute_path")"
}

record_directory() {
    local absolute_path="$1"
    local relative_path="${absolute_path#"$PROJECT_ROOT/"}"
    local mode
    mode=$(/usr/bin/stat -f '%Lp' "$absolute_path")
    printf 'directory\t%s\t%s\n' "$mode" "$relative_path"
}

for relative_path in "${required_inputs[@]}"; do
    absolute_path="$PROJECT_ROOT/$relative_path"
    if [[ -f "$absolute_path" || -L "$absolute_path" ]]; then
        if [[ -L "$absolute_path" ]]; then
            record_symlink "$absolute_path"
        else
            record_file "$absolute_path"
        fi
        continue
    fi

    /usr/bin/find "$absolute_path" \( -type d -o -type f -o -type l \) -print0 |
        while IFS= read -r -d '' nested_path; do
            if [[ -L "$nested_path" ]]; then
                record_symlink "$nested_path"
            elif [[ -d "$nested_path" ]]; then
                record_directory "$nested_path"
            else
                record_file "$nested_path"
            fi
        done
done | LC_ALL=C /usr/bin/sort > "$records_file"

/usr/bin/shasum -a 256 "$records_file" | /usr/bin/awk '{ print $1 }'
