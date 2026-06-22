#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node --experimental-strip-types "$PROJECT_ROOT/BridgeWeb/scripts/verify-bridge-viewer-benchmark.ts"
