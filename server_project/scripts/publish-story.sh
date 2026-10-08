#!/usr/bin/env sh
set -eu
FILE=${1:?usage: publish-story.sh story.json [base-url] [admin-token]}
BASE_URL=${2:-http://127.0.0.1:8080}
ADMIN_TOKEN=${3:?admin token is required}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/validate-story.sh" "$FILE"
curl --fail-with-body -sS -X POST "${BASE_URL%/}/api/admin/stories/publish" -H "Content-Type: application/json" -H "X-Admin-Token: ${ADMIN_TOKEN}" --data-binary "@${FILE}"
printf '\n'
