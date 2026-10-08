#!/usr/bin/env sh
set -eu
FILE=${1:?usage: validate-story.sh story.json}
python3 - "$FILE" <<'PY'
import json, re, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    doc = json.load(handle)
errors = []
if doc.get("schemaVersion") != 1: errors.append("schemaVersion must be 1")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{1,127}", str(doc.get("storyId", ""))): errors.append("invalid storyId")
if not str(doc.get("title", "")).strip() or len(str(doc.get("title", ""))) > 200: errors.append("invalid title")
ids = set()
for chapter in doc.get("chapters", []):
    for memory in chapter.get("memories", []):
        ident = memory.get("id")
        if not ident or ident in ids: errors.append(f"duplicate or empty memory id: {ident}")
        ids.add(ident)
        if not str(memory.get("content", "")).strip() or len(str(memory.get("content", ""))) > 20000: errors.append(f"invalid memory: {ident}")
if errors:
    for error in errors: print(error, file=sys.stderr)
    raise SystemExit(1)
print(f"OK: {path} ({len(ids)} memories)")
PY
