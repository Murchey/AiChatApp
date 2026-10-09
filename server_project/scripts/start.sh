#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PORT="${PORT:-8080}"
DATA_DIR="${AICHAT_DATA_DIR:-$ROOT/data}"
mkdir -p "$DATA_DIR"
export AICHAT_PORT="$PORT" AICHAT_DATA_DIR="$DATA_DIR"
cd "$ROOT"
if [ "${BUILD:-0}" = "1" ]; then ./gradlew bootJar; fi
if [ -f build/libs/aichat-backend.jar ]; then
  exec java -jar build/libs/aichat-backend.jar
else
  exec ./gradlew bootRun
fi

