#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"
set -a
. ./aichat.env
set +a
exec java -jar "$ROOT/aichat-backend.jar"
