#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BINARY="$(mktemp -d)/ClaudeBarTests"

swiftc \
    "$PROJECT_DIR/Sources/Models.swift" \
    "$PROJECT_DIR/Sources/TokenStatsScanner.swift" \
    "$PROJECT_DIR/Sources/UsageCacheStore.swift" \
    "$PROJECT_DIR/Tests/main.swift" \
    -o "$TEST_BINARY"

"$TEST_BINARY"
