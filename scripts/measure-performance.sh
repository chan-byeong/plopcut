#!/bin/sh
# Generates a deterministic 5,000-drop library in a temp dir and runs the PlopcutCore performance tests on it.
# Usage: scripts/measure-performance.sh [COUNT]
set -eu
COUNT="${1:-5000}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$(mktemp -d "${TMPDIR:-/tmp}/plopcut-perf.XXXXXX")"
trap 'rm -rf "$DIR"' EXIT
python3 "$ROOT/scripts/generate-perf-library.py" "$DIR/library" "$COUNT"
cd "$ROOT/PlopcutCore"
PLOPCUT_PERF_LIBRARY="$DIR/library" swift test -c release -Xswiftc -enable-testing --filter PerformanceTests 2>&1 | grep -E "PERF|passed|failed|error" || true
