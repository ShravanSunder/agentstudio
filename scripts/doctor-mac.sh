#!/usr/bin/env bash
set -euo pipefail

project_root="${PROJECT_ROOT:-$(pwd)}"

issues=0
warnings=0

report_ok() {
  printf '[doctor-mac] OK: %s\n' "$1"
}

report_warn() {
  printf '[doctor-mac] WARN: %s\n' "$1"
  warnings=$((warnings + 1))
}

report_error() {
  printf '[doctor-mac] ERROR: %s\n' "$1"
  issues=$((issues + 1))
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  report_error "doctor-mac is intended for macOS hosts only."
fi

if [[ -f "$project_root/vendor/ghostty/build.zig" && -f "$project_root/vendor/zmx/build.zig" ]]; then
  report_ok "git submodules are populated"
else
  report_error "git submodules are missing. Run: git submodule update --init --recursive"
fi

if xcode_path="$(xcode-select -p 2>/dev/null)"; then
  report_ok "xcode-select points at $xcode_path"
else
  report_error "xcode-select is not configured"
fi

if xcode_version_output="$(xcodebuild -version 2>/dev/null)"; then
  report_ok "$(printf '%s' "$xcode_version_output" | tr '\n' ' ' | sed 's/  */ /g')"
  xcode_version="$(printf '%s\n' "$xcode_version_output" | awk '/^Xcode / {print $2; exit}')"
  if [[ -n "$xcode_version" && "$xcode_version" != "26.2" ]]; then
    report_warn "local Xcode ($xcode_version) differs from the GitHub Actions baseline (26.2 on macos-26-arm64)"
  fi
else
  report_error "xcodebuild is unavailable. Install and finish launching Xcode first."
fi

if sdk_path="$(xcrun --show-sdk-path 2>/dev/null)"; then
  report_ok "macOS SDK path: $sdk_path"
else
  report_error "xcrun could not resolve the active macOS SDK"
fi

if metal_path="$(xcrun --find metal 2>/dev/null)"; then
  report_ok "metal tool found at $metal_path"
else
  report_error "xcrun could not find metal. Install the Metal Toolchain with: xcodebuild -downloadComponent MetalToolchain"
fi

if zig_version="$(zig version 2>/dev/null)"; then
  report_ok "zig version $zig_version"
else
  report_error "zig is unavailable. Run: mise install"
fi

problem_vars=(
  CC
  CXX
  CFLAGS
  CXXFLAGS
  CPPFLAGS
  LDFLAGS
  CPATH
  LIBRARY_PATH
  SDKROOT
  DEVELOPER_DIR
  MACOSX_DEPLOYMENT_TARGET
)

present_vars=()
for var_name in "${problem_vars[@]}"; do
  if [[ -n "${!var_name-}" ]]; then
    present_vars+=("$var_name=${!var_name}")
  fi
done

if (( ${#present_vars[@]} > 0 )); then
  report_error "compiler/linker environment is polluted for local Zig builds:"
  for entry in "${present_vars[@]}"; do
    printf '  - %s\n' "$entry"
  done
  printf '[doctor-mac] INFO: rerun setup/build from a scrubbed shell env, for example:\n'
  printf '  env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u CPATH -u LIBRARY_PATH -u SDKROOT -u DEVELOPER_DIR -u MACOSX_DEPLOYMENT_TARGET mise run setup\n'
else
  report_ok "compiler/linker environment is clean for Zig"
fi

if (( issues > 0 )); then
  printf '[doctor-mac] FAILED with %d issue(s) and %d warning(s)\n' "$issues" "$warnings"
  exit 1
fi

if (( warnings > 0 )); then
  printf '[doctor-mac] PASSED with %d warning(s)\n' "$warnings"
else
  printf '[doctor-mac] PASSED\n'
fi
