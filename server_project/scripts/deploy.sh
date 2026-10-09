#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.aichat/server}"
PORT="${PORT:-8080}"
mkdir -p "$INSTALL_DIR/data"
cd "$ROOT"
if [ "${SKIP_TESTS:-0}" != "1" ]; then ./gradlew test; fi
./gradlew bootJar
cp build/libs/aichat-backend.jar "$INSTALL_DIR/aichat-backend.jar"
cat > "$INSTALL_DIR/aichat.env" <<EOF
AICHAT_PORT=$PORT
AICHAT_DATA_DIR=$INSTALL_DIR/data
EOF
printf '部署完成：%s\n' "$INSTALL_DIR"
printf '启动命令：java -jar %s\n' "$INSTALL_DIR/aichat-backend.jar"

