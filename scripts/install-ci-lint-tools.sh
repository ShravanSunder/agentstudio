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

if [[ "$(uname -s)" == Linux ]]; then
  case "$(uname -m)" in
    x86_64)
      swiftlint_arch=amd64
      swiftlint_sha256=caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d
      ;;
    aarch64|arm64)
      swiftlint_arch=arm64
      swiftlint_sha256=9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8
      ;;
    *)
      echo "unsupported Linux SwiftLint architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
  swiftlint_archive="$tool_root/swiftlint_linux_${swiftlint_arch}.zip"
  curl -fsSL "https://github.com/realm/SwiftLint/releases/download/0.65.1/swiftlint_linux_${swiftlint_arch}.zip" -o "$swiftlint_archive"
  printf '%s  %s\n' "$swiftlint_sha256" "$swiftlint_archive" | sha256sum --check
  unzip -q "$swiftlint_archive" -d "$tool_root/swiftlint-linux"
  swiftlint_executable="$(find "$tool_root/swiftlint-linux" -type f -name swiftlint -print -quit)"
  test -n "$swiftlint_executable"
  chmod 755 "$swiftlint_executable"
  swiftlint_bin="$(dirname "$swiftlint_executable")"

  sourcekit_library="$(find /usr/lib -name libsourcekitdInProc.so -print -quit)"
  test -n "$sourcekit_library"
  test -f "$sourcekit_library"
  export LINUX_SOURCEKIT_LIB_PATH="$sourcekit_library"
  echo "LINUX_SOURCEKIT_LIB_PATH=$sourcekit_library" >> "$GITHUB_ENV"
else
  mise install swiftlint@0.65.1
  swiftlint_bin="$(mise where swiftlint@0.65.1)"
fi

echo "$tool_bin" >> "$GITHUB_PATH"
if [[ "$swiftlint_bin" != "$tool_bin" ]]; then
  echo "$swiftlint_bin" >> "$GITHUB_PATH"
fi
"$tool_bin/swift-format" --version
"$swiftlint_bin/swiftlint" version
"$swiftlint_bin/swiftlint" rules --enabled --config .swiftlint.yml
