#!/usr/bin/env sh
set -eu
BASE_URL=${1:-http://127.0.0.1:8080}
ADMIN_TOKEN=${2:?usage: generate-invite.sh [base-url] admin-token [max-uses] [expires-hours]}
MAX_USES=${3:-1}
EXPIRES=${4:-0}
curl --fail-with-body -sS -X POST "${BASE_URL%/}/api/admin/invites" -H "Content-Type: application/json" -H "X-Admin-Token: ${ADMIN_TOKEN}" -d "{\"maxUses\":${MAX_USES},\"expiresInHours\":${EXPIRES}}"
printf '\n'
