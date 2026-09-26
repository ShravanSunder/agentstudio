#!/usr/bin/env bash
set -euo pipefail

# Both CI operating systems build the same upstream swift-format revision.
# The 603.0.0 release publishes source, but no runnable release artifact.
swift_format_revision=d54c5be7afba3e5f52ae29e2371e444a3c2a49c1
tool_root="${RUNNER_TEMP:?RUNNER_TEMP is required}/agentstudio-lint-tools"
format_source="$tool_root/swift-format-source"
format_build="$tool_root/swift-format-build"
tool_bin="$tool_root/bin"
mkdir -p "$tool_bin"
git clone --depth 1 --branch 603.0.0 https://github.com/swiftlang/swift-format.git "$format_source"
test "$(git -C "$format_source" rev-parse HEAD)" = "$swift_format_revision"
swift build -c release --package-path "$format_source" --scratch-path "$format_build" --product swift-format
ln -s "$format_build/release/swift-format" "$tool_bin/swift-format"

mise install swiftlint@0.65.1
swiftlint_bin="$(mise where swiftlint@0.65.1)"

if [[ "$(uname -s)" == Linux ]]; then
  swift_binary="$(readlink -f "$(command -v swift)")"
  sourcekit_library="$(dirname "$(dirname "$swift_binary")")/lib/libsourcekitdInProc.so"
  test -f "$sourcekit_library"
  export LINUX_SOURCEKIT_LIB_PATH="$sourcekit_library"
  echo "LINUX_SOURCEKIT_LIB_PATH=$sourcekit_library" >> "$GITHUB_ENV"
fi

echo "$tool_bin" >> "$GITHUB_PATH"
echo "$swiftlint_bin" >> "$GITHUB_PATH"
"$tool_bin/swift-format" --version
"$swiftlint_bin/swiftlint" version
"$swiftlint_bin/swiftlint" rules --enabled --config .swiftlint.yml
