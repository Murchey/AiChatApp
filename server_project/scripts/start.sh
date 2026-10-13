#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
if [ -f "$ROOT/config/local.env" ]; then
  set -a
  . "$ROOT/config/local.env"
  set +a
fi
PORT="${PORT:-${AICHAT_PORT:-8080}}"
DATA_DIR="${AICHAT_DATA_DIR:-$ROOT/data}"
mkdir -p "$DATA_DIR"
export AICHAT_PORT="$PORT" AICHAT_DATA_DIR="$DATA_DIR"
cd "$ROOT"
if [ "${SKIP_BUILD:-0}" != "1" ] || [ "${BUILD:-0}" = "1" ]; then SKIP_TESTS=1 sh ./scripts/build.sh; fi
if [ -f build/libs/aichat-backend.jar ]; then
  exec java -jar build/libs/aichat-backend.jar
else
  printf 'JAR 不存在，请先运行 scripts/build.sh\n' >&2
  exit 1
fi

