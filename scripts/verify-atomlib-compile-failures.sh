#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
FIXTURE_PATH="${PROJECT_ROOT}/Tests/AgentStudioTests/Fixtures/AtomLibCompileFailures/EagerDerivedAtomNonSendableRequest.swift.fixture"
SOURCE_PATH="${PROJECT_ROOT}/Sources/AgentStudio/Infrastructure/AtomLib/EagerDerivedAtom.swift"
PACKAGE_NAME="$(basename "${PROJECT_ROOT}" | tr '.-' '__')"
DIAGNOSTIC_PATH="$(mktemp -t agentstudio-atomlib-compile-negative)"
FIXTURE_TEMP_BASE="$(mktemp -t agentstudio-atomlib-non-sendable-request)"
FIXTURE_SWIFT_PATH="${FIXTURE_TEMP_BASE}.swift"
mv "${FIXTURE_TEMP_BASE}" "${FIXTURE_SWIFT_PATH}"
cp "${FIXTURE_PATH}" "${FIXTURE_SWIFT_PATH}"
trap 'rm -f "${DIAGNOSTIC_PATH}" "${FIXTURE_SWIFT_PATH}"' EXIT

set +e
swiftc \
    -typecheck \
    -swift-version 6 \
    -strict-concurrency=complete \
    -package-name "${PACKAGE_NAME}" \
    "${SOURCE_PATH}" \
    "${FIXTURE_SWIFT_PATH}" > "${DIAGNOSTIC_PATH}" 2>&1
compile_status=$?
set -e

if [[ ${compile_status} -eq 0 ]]; then
    echo "[atomlib-compile-negative] ERROR non-Sendable request compiled successfully" >&2
    exit 1
fi

if ! grep -Fq "EagerDerivedAtomNonSendableRequest" "${DIAGNOSTIC_PATH}" || \
    ! grep -Fq "does not conform to the 'Sendable' protocol" "${DIAGNOSTIC_PATH}"
then
    echo "[atomlib-compile-negative] ERROR fixture failed for an unexpected reason" >&2
    sed -n '1,120p' "${DIAGNOSTIC_PATH}" >&2
    exit 1
fi

echo "[atomlib-compile-negative] PASS EagerDerivedAtom rejects a non-Sendable request"
