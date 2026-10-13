#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.aichat/server}"
PORT="${PORT:-8080}"
mkdir -p "$INSTALL_DIR/data"
cd "$ROOT"
sh ./scripts/build.sh
cp build/libs/aichat-backend.jar "$INSTALL_DIR/aichat-backend.jar"
if [ ! -f "$INSTALL_DIR/aichat.env" ]; then
cat > "$INSTALL_DIR/aichat.env" <<EOF
AICHAT_PORT=$PORT
AICHAT_DATA_DIR=$INSTALL_DIR/data
EOF
fi
cp scripts/launch.sh "$INSTALL_DIR/launch.sh"
printf '部署完成：%s\n' "$INSTALL_DIR"
printf '启动命令：sh "%s"\n' "$INSTALL_DIR/launch.sh"

