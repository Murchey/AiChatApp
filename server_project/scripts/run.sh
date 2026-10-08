#!/usr/bin/env sh
set -eu
PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export AICHAT_PORT="${AICHAT_PORT:-8080}"
export AICHAT_DATA_DIR="${AICHAT_DATA_DIR:-$PROJECT_ROOT/data}"
mkdir -p "$AICHAT_DATA_DIR"
cd "$PROJECT_ROOT"
exec ./gradlew bootRun
