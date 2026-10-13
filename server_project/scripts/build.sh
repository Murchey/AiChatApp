#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT/admin-panel"
if [ ! -d node_modules ]; then npm ci; fi
npm run build
cd "$ROOT"
if [ "${SKIP_TESTS:-0}" != "1" ]; then sh ./gradlew test; fi
sh ./gradlew bootJar
