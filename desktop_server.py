#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AiChat 电脑端服务
- 托管完整桌面客户端（index.html）
- 局域网同步：接收手机 AiChat 备份并解析到本地数据
- 提供聊天/角色/朋友圈/设置等数据 API

用法：
  python desktop_server.py --port 8765
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import socket
import sys
import threading
import zipfile
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
INDEX_FILE = ROOT / "index.html"


def lan_ip_guess() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def _unwrap_pref(value):
    """备份 prefs.json 中 {t,v} 包装还原为原始值。"""
    if isinstance(value, dict) and "t" in value and "v" in value:
        return value["v"]
    return value


def _maybe_json(value):
    if isinstance(value, str):
        s = value.strip()
        if s.startswith("{") or s.startswith("["):
            try:
                return json.loads(s)
            except Exception:
                return value
    return value


class DesktopState:
    def __init__(self, data_dir: Path, port: int):
        self.data_dir = data_dir
        self.port = port
        self.pair_code = f"{os.urandom(3).hex()[:6]}"
        self.logs: list[str] = []
        self.lock = threading.Lock()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        (self.data_dir / "backups").mkdir(exist_ok=True)
        self.app_data_path = self.data_dir / "app_data.json"
        self.log(f"服务启动 · 数据目录 {self.data_dir}")
        self.log(f"配对码 {self.pair_code} · 监听 0.0.0.0:{port}")

    # ── 日志 ─────────────────────────────────────────────
    def log(self, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{stamp}] {message}"
        with self.lock:
            self.logs.append(line)
            del self.logs[:-100]
        print(line, flush=True)

    # ── 备份文件 ─────────────────────────────────────────
    def backup_dir(self) -> Path:
        return self.data_dir / "backups"

    def files(self) -> list[dict]:
        items = []
        bdir = self.backup_dir()
        if not bdir.exists():
            return items
        for p in sorted(bdir.glob("*"), key=lambda x: x.stat().st_mtime, reverse=True):
            if not p.is_file():
                continue
            stat = p.st_size and p.stat()
            name = p.name
            kind = "备份"
            if name.startswith("aichat_auto_") or name.startswith("aichat_sync_"):
                kind = "自动/同步"
            elif name.startswith("aichat_backup_"):
                kind = "手动"
            items.append(
                {
                    "name": name,
                    "size": p.stat().st_size,
                    "time": datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M"),
                    "kind": kind,
                }
            )
        return items

    # ── 解析备份 → 应用数据 ───────────────────────────────
    def load_app_data(self) -> dict:
        if self.app_data_path.exists():
            try:
                return json.loads(self.app_data_path.read_text(encoding="utf-8"))
            except Exception:
                pass
        return {
            "chats": [],
            "characters": [],
            "groups": [],
            "moments": [],
            "settings": {},
            "source": "empty",
            "updated": None,
        }

    def save_app_data(self, data: dict) -> None:
        data["updated"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self.app_data_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def extract_backup_zip(self, zip_bytes: bytes, name: str) -> dict:
        """从手机备份 zip 解析 prefs.json，生成桌面端可读数据。"""
        prefs_raw = {}
        try:
            with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
                if "prefs.json" in zf.namelist():
                    prefs_raw = json.loads(zf.read("prefs.json").decode("utf-8"))
        except Exception as exc:
            raise ValueError(f"无法解析备份 zip：{exc}")

        prefs = {k: _maybe_json(_unwrap_pref(v)) for k, v in prefs_raw.items()}

        # 角色
        characters = []
        chars = prefs.get("characters_v1")
        if isinstance(chars, list):
            for c in chars:
                if not isinstance(c, dict):
                    continue
                characters.append(
                    {
                        "id": c.get("id") or c.get("name") or "c",
                        "name": c.get("name") or "未命名角色",
                        "signature": c.get("signature") or "",
                        "avatar": c.get("avatar") or "",
                        "greeting": (c.get("greeting") or c.get("firstMessage") or "")[:80],
                    }
                )

        # 会话
        chats = []
        convs = prefs.get("chat_conversations_v1")
        messages = prefs.get("chat_messages_v1") or {}
        if isinstance(convs, list):
            for conv in convs:
                if not isinstance(conv, dict):
                    continue
                cid = conv.get("id") or ""
                msgs = []
                raw_msgs = messages.get(cid) if isinstance(messages, dict) else None
                if isinstance(raw_msgs, list):
                    for m in raw_msgs[-30:]:
                        if not isinstance(m, dict):
                            continue
                        msgs.append(
                            {
                                "id": m.get("id"),
                                "isFromUser": bool(m.get("is_from_user") or m.get("isFromUser")),
                                "type": m.get("type") or m.get("messageType") or "text",
                                "content": m.get("content") or "",
                                "time": m.get("created_at") or m.get("createdAt") or "",
                                "senderName": m.get("sender_name") or m.get("senderName") or "",
                            }
                        )
                chats.append(
                    {
                        "id": cid,
                        "characterId": conv.get("character_id") or conv.get("characterId") or "",
                        "title": conv.get("character_name") or conv.get("characterName") or "会话",
                        "avatar": conv.get("character_avatar") or conv.get("characterAvatar") or "",
                        "lastMessage": conv.get("last_message") or conv.get("lastMessage") or "",
                        "lastTime": conv.get("last_message_time") or conv.get("lastMessageTime") or "",
                        "unread": conv.get("unread_count") or conv.get("unreadCount") or 0,
                        "pinned": bool(conv.get("pinned")),
                        "messages": msgs,
                    }
                )
            chats.sort(key=lambda x: (not x.get("pinned"), str(x.get("lastTime") or "")), reverse=True)

        # 群聊
        groups = []
        g = prefs.get("group_chats_v1")
        if isinstance(g, list):
            for item in g:
                if not isinstance(item, dict):
                    continue
                groups.append(
                    {
                        "id": item.get("id") or "",
                        "name": item.get("name") or "群聊",
                        "memberCount": len(item.get("memberIds") or item.get("members") or []),
                        "lastMessage": item.get("last_message") or item.get("lastMessage") or "",
                    }
                )

        # 朋友圈（从角色 moments 相关键尽量取）
        moments = []
        raw_moments = prefs.get("moments_v1") or prefs.get("user_moments_v1")
        if isinstance(raw_moments, list):
            for m in raw_moments[:50]:
                if not isinstance(m, dict):
                    continue
                moments.append(
                    {
                        "id": m.get("id") or "",
                        "author": m.get("author_name") or m.get("author") or "角色",
                        "content": m.get("content") or m.get("text") or "",
                        "time": m.get("created_at") or m.get("time") or "",
                        "likes": m.get("like_count") or 0,
                        "comments": len(m.get("comments") or []),
                    }
                )

        settings = {
            "theme": prefs.get("theme_mode") or "system",
            "uiStyle": prefs.get("ui_style") or "",
            "bubbleStyle": prefs.get("bubble_style") or "",
            "allowStickerSend": prefs.get("allow_sticker_send"),
            "unreadNotify": prefs.get("unread_notify"),
        }

        return {
            "chats": chats,
            "characters": characters,
            "groups": groups,
            "moments": moments,
            "settings": settings,
            "source": name,
            "prefsKeys": sorted(list(prefs.keys()))[:80],
        }

    def import_backup_bytes(self, zip_bytes: bytes, name: str) -> dict:
        bdir = self.backup_dir()
        safe = re.sub(r"[^\w.\-]+", "_", name).strip("._") or "aichat_backup.zip"
        if not safe.lower().endswith((".zip", ".aibackup")):
            safe += ".zip"
        target = bdir / safe
        seq = 1
        while target.exists():
            target = bdir / f"{target.stem}_{seq}{target.suffix}"
            seq += 1
        target.write_bytes(zip_bytes)
        app = self.extract_backup_zip(zip_bytes, target.name)
        self.save_app_data(app)
        self.log(f"已同步并解析 {target.name}（{len(zip_bytes)} 字节）→ 桌面数据")
        return app

    def status(self) -> dict:
        with self.lock:
            logs = list(self.logs)
        app = self.load_app_data()
        return {
            "running": True,
            "port": self.port,
            "listen": f"0.0.0.0:{self.port}",
            "host": lan_ip_guess(),
            "pairCode": self.pair_code,
            "files": self.files(),
            "logs": logs,
            "dataDir": str(self.data_dir),
            "appDataUpdated": app.get("updated"),
            "chatCount": len(app.get("chats") or []),
            "characterCount": len(app.get("characters") or []),
        }

    def reset_pair(self) -> str:
        self.pair_code = f"{os.urandom(3).hex()[:6]}"
        self.log(f"配对码已重置为 {self.pair_code}")
        return self.pair_code


STATE: DesktopState | None = None


class Handler(BaseHTTPRequestHandler):
    server_version = "AiChatDesktop/2.0"

    def log_message(self, fmt: str, *args) -> None:
        if args and str(args[0]).startswith("POST"):
            print(f"[http] {args[0]}", flush=True)

    def _json(self, code: int, payload: dict | list) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length > 0 else b""

    def do_GET(self) -> None:  # noqa: N802
        assert STATE is not None
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ("/", "/index.html"):
            if INDEX_FILE.exists():
                data = INDEX_FILE.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self._json(404, {"ok": False, "error": "index.html not found"})
            return

        if path == "/api/status":
            self._json(200, STATE.status())
            return

        if path == "/api/appdata":
            self._json(200, STATE.load_app_data())
            return

        self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        assert STATE is not None
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path == "/api/reset_pair":
            self._json(200, {"ok": True, "pairCode": STATE.reset_pair()})
            return

        if path == "/api/clear":
            deleted = 0
            for p in STATE.backup_dir().glob("*"):
                if p.is_file():
                    try:
                        p.unlink()
                        deleted += 1
                    except OSError:
                        pass
            # 清空解析数据但保留服务
            STATE.save_app_data(
                {
                    "chats": [],
                    "characters": [],
                    "groups": [],
                    "moments": [],
                    "settings": {},
                    "source": "empty",
                }
            )
            STATE.log(f"已清空同步备份 {deleted} 份")
            self._json(200, {"ok": True, "deleted": deleted})
            return

        if path == "/api/port":
            body = self._read_body()
            try:
                data = json.loads(body.decode("utf-8") or "{}")
                port = int(data.get("port") or 0)
            except Exception:
                self._json(400, {"ok": False, "error": "invalid json"})
                return
            if not (1024 <= port <= 65535):
                self._json(400, {"ok": False, "error": "port out of range"})
                return
            STATE.port = port
            STATE.log(f"端口改为 {port}，重启 desktop_server 后生效")
            self._json(200, {"ok": True, "port": port})
            return

        if path == "/api/sync":
            pair = (
                self.headers.get("X-Pair-Code")
                or (query.get("pair") or [""])[0]
                or ""
            ).strip()
            name = (query.get("name") or ["backup.zip"])[0].strip()
            kind = (query.get("kind") or ["sync"])[0].strip()
            if pair != STATE.pair_code:
                STATE.log("配对失败：配对码不匹配")
                self._json(403, {"ok": False, "error": "pair code mismatch"})
                return
            body = self._read_body()
            if len(body) < 16:
                self._json(400, {"ok": False, "error": "empty payload"})
                return
            try:
                app = STATE.import_backup_bytes(body, name)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
                return
            self._json(
                200,
                {
                    "ok": True,
                    "kind": kind,
                    "chats": len(app.get("chats") or []),
                    "characters": len(app.get("characters") or []),
                },
            )
            return

        if path == "/api/demo":
            # 载入演示数据，便于无手机时预览完整电脑端
            demo = {
                "chats": [
                    {
                        "id": "demo1",
                        "characterId": "c1",
                        "title": "爱弥斯",
                        "avatar": "",
                        "lastMessage": "今晚的星空很适合写诗。",
                        "lastTime": "2026-09-27 20:10",
                        "unread": 2,
                        "pinned": True,
                        "messages": [
                            {
                                "id": "m1",
                                "isFromUser": True,
                                "type": "text",
                                "content": "在吗？",
                                "time": "2026-09-27 20:02",
                                "senderName": "",
                            },
                            {
                                "id": "m2",
                                "isFromUser": False,
                                "type": "text",
                                "content": "在的。今晚的星空很适合写诗。",
                                "time": "2026-09-27 20:10",
                                "senderName": "爱弥斯",
                            },
                        ],
                    },
                    {
                        "id": "demo2",
                        "characterId": "c2",
                        "title": "旅行助手",
                        "avatar": "",
                        "lastMessage": "已为你整理好周末行程。",
                        "lastTime": "2026-09-26 18:40",
                        "unread": 0,
                        "pinned": False,
                        "messages": [
                            {
                                "id": "m3",
                                "isFromUser": True,
                                "type": "text",
                                "content": "帮我规划周末。",
                                "time": "2026-09-26 18:30",
                                "senderName": "",
                            },
                            {
                                "id": "m4",
                                "isFromUser": False,
                                "type": "text",
                                "content": "已为你整理好周末行程。",
                                "time": "2026-09-26 18:40",
                                "senderName": "旅行助手",
                            },
                        ],
                    },
                ],
                "characters": [
                    {
                        "id": "c1",
                        "name": "爱弥斯",
                        "signature": "来自终末地的员工",
                        "avatar": "",
                        "greeting": "晚上好。",
                    },
                    {
                        "id": "c2",
                        "name": "旅行助手",
                        "signature": "说走就走",
                        "avatar": "",
                        "greeting": "想去哪里？",
                    },
                ],
                "groups": [
                    {
                        "id": "g1",
                        "name": "周末出游群",
                        "memberCount": 5,
                        "lastMessage": "明早八点集合",
                    }
                ],
                "moments": [
                    {
                        "id": "p1",
                        "author": "爱弥斯",
                        "content": "今晚的星空很适合写诗。",
                        "time": "2026-09-27 19:00",
                        "likes": 12,
                        "comments": 3,
                    },
                    {
                        "id": "p2",
                        "author": "旅行助手",
                        "content": "分享一条冷门徒步路线。",
                        "time": "2026-09-26 12:00",
                        "likes": 8,
                        "comments": 1,
                    },
                ],
                "settings": {
                    "theme": "system",
                    "uiStyle": "sleek",
                    "bubbleStyle": "sr",
                    "allowStickerSend": True,
                    "unreadNotify": True,
                },
                "source": "demo",
            }
            STATE.save_app_data(demo)
            STATE.log("已载入演示数据")
            self._json(200, {"ok": True})
            return

        if path == "/api/chat/send":
            body = self._read_body()
            try:
                data = json.loads(body.decode("utf-8") or "{}")
                chat_id = data.get("chatId") or ""
                text = (data.get("text") or "").strip()
            except Exception:
                self._json(400, {"ok": False, "error": "invalid json"})
                return
            if not text:
                self._json(400, {"ok": False, "error": "empty text"})
                return
            app = STATE.load_app_data()
            reply = {
                "id": f"r{int(datetime.now().timestamp() * 1000)}",
                "isFromUser": False,
                "type": "text",
                "content": f"（电脑端演示回复）收到：{text}",
                "time": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "senderName": "",
            }
            for chat in app.get("chats") or []:
                if chat.get("id") == chat_id:
                    chat.setdefault("messages", []).append(
                        {
                            "id": f"u{int(datetime.now().timestamp() * 1000)}",
                            "isFromUser": True,
                            "type": "text",
                            "content": text,
                            "time": datetime.now().strftime("%Y-%m-%d %H:%M"),
                            "senderName": "",
                        }
                    )
                    chat["messages"].append(reply)
                    chat["lastMessage"] = text
                    chat["lastTime"] = reply["time"]
                    break
            else:
                app.setdefault("chats", []).append(
                    {
                        "id": chat_id or "local",
                        "characterId": "",
                        "title": "新会话",
                        "avatar": "",
                        "lastMessage": text,
                        "lastTime": reply["time"],
                        "unread": 0,
                        "pinned": False,
                        "messages": [
                            {
                                "id": "u0",
                                "isFromUser": True,
                                "type": "text",
                                "content": text,
                                "time": reply["time"],
                                "senderName": "",
                            },
                            reply,
                        ],
                    }
                )
            STATE.save_app_data(app)
            self._json(200, {"ok": True, "reply": reply})
            return

        self._json(404, {"ok": False, "error": "not found"})


def main() -> None:
    parser = argparse.ArgumentParser(description="AiChat desktop + LAN sync")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data", type=str, default="desktop_sync_data")
    args = parser.parse_args()

    data_dir = Path(args.data)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir

    global STATE
    STATE = DesktopState(data_dir, args.port)

    httpd = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("=" * 52)
    print(" AiChat 电脑端已启动")
    print(f"  界面地址 : http://{lan_ip_guess()}:{args.port}")
    print(f"  配对码   : {STATE.pair_code}")
    print(f"  数据目录 : {data_dir}")
    print("  手机：设置 → 数据备份 → 局域网同步")
    print("  热点：电脑连手机热点后填电脑 IP:端口")
    print("=" * 52)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
