#!/usr/bin/env sh
set -eu
BASE_URL=${1:-http://127.0.0.1:8080}
curl --fail-with-body -sS "${BASE_URL%/}/api/stories${2:-}"
printf '\n'
