#!/usr/bin/env python3
"""gen_roster.py — 把 agents/*/agent.yml 合併成群組主持人用的名冊。

用法（由 gen-roster.sh 呼叫）：
    FEISHU_APP_ID=... FEISHU_APP_SECRET=... FEISHU_DOMAIN=lark \
    python3 scripts/gen_roster.py [chat_id]

輸出：agents/roster.yaml

行為：
  1. 掃描 agents/*/agent.yml，收集 name / title / description / capabilities
  2. 若給了 FEISHU 憑證，呼叫 Feishu API 列出群成員，用 bot 顯示名稱比對，
     自動補上 open_id（失敗時保留 agent.yml 裡手動填的值）
  3. 永不輸出任何金鑰
"""
from __future__ import annotations

import glob
import json
import os
import sys
import urllib.error
import urllib.request

try:
    import yaml
except ImportError:
    sys.exit("需要 PyYAML：pip install pyyaml（Hermes venv 內已有）")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AGENTS_DIR = os.path.join(ROOT, "agents")
OUT = os.path.join(AGENTS_DIR, "roster.yaml")


def load_agents() -> list[dict]:
    agents = []
    for path in sorted(glob.glob(os.path.join(AGENTS_DIR, "*", "agent.yml"))):
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        data["_path"] = os.path.relpath(path, ROOT)
        agents.append(data)
    return agents


def feishu_members(chat_id: str) -> dict[str, str]:
    """回傳 {顯示名稱: open_id}；任何失敗都回空 dict，不讓名冊生成中斷。"""
    app_id = os.environ.get("FEISHU_APP_ID", "")
    secret = os.environ.get("FEISHU_APP_SECRET", "")
    if not app_id or not secret or not chat_id:
        return {}
    base = "https://open.larksuite.com" if os.environ.get("FEISHU_DOMAIN") == "lark" else "https://open.feishu.cn"

    def call(path: str, payload=None, token=None):
        req = urllib.request.Request(base + path)
        if payload is not None:
            req.data = json.dumps(payload).encode()
            req.add_header("Content-Type", "application/json")
        if token:
            req.add_header("Authorization", "Bearer " + token)
        return json.load(urllib.request.urlopen(req, timeout=20))

    try:
        token = call("/open-apis/auth/v3/tenant_access_token/internal",
                     {"app_id": app_id, "app_secret": secret})["tenant_access_token"]
        res = call(f"/open-apis/im/v1/chats/{chat_id}/members?member_id_type=open_id&page_size=100",
                   token=token)
        # bot 自己通常不會出現在群成員清單裡，另外查
        try:
            me = call("/open-apis/bot/v3/info", token=token).get("bot", {})
            if me.get("open_id"):
                res.setdefault("data", {}).setdefault("items", []).append(
                    {"name": me.get("app_name", ""), "member_id": me["open_id"]})
        except Exception:  # noqa: BLE001
            pass
    except (urllib.error.HTTPError, urllib.error.URLError, KeyError) as exc:
        print(f"  ! 無法從 Feishu 取得成員（{exc}），保留 agent.yml 內的值", file=sys.stderr)
        return {}

    out = {}
    for item in res.get("data", {}).get("items", []):
        name = (item.get("name") or "").strip()
        mid = item.get("member_id") or ""
        if name and mid:
            out[name] = mid
    return out


def main() -> None:
    chat_id = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("FEISHU_GROUP_CHAT_ID", "")
    agents = load_agents()
    members = feishu_members(chat_id)

    resolved = 0
    for a in agents:
        feishu = a.setdefault("feishu", {})
        if not feishu.get("open_id"):
            guess = members.get(a.get("name", "")) or members.get(a.get("title", ""))
            if guess:
                feishu["open_id"] = guess
                resolved += 1

    roster = {
        "generated_by": "scripts/gen_roster.py",
        "group_chat_id": chat_id,
        "team": [{
            "name": a.get("name"),
            "title": a.get("title"),
            "description": a.get("description"),
            "capabilities": a.get("capabilities", []),
            "cannot": a.get("cannot", []),
            "open_id": (a.get("feishu") or {}).get("open_id", ""),
            "is_moderator": bool((a.get("feishu") or {}).get("is_moderator")),
            "require_mention": (a.get("feishu") or {}).get("require_mention", True),
        } for a in agents],
    }

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("# 自動生成，請勿手改（改 agents/*/agent.yml 後重跑 scripts/gen-roster.sh）\n")
        yaml.safe_dump(roster, fh, allow_unicode=True, sort_keys=False)

    print(f"✓ 名冊已寫入 {os.path.relpath(OUT, ROOT)}")
    print(f"  agent 數：{len(agents)}　自動補到 open_id：{resolved}")
    for m in roster["team"]:
        flag = "（主持人）" if m["is_moderator"] else ""
        oid = (m["open_id"][:10] + "…") if m["open_id"] else "⚠ 缺 open_id"
        print(f"  - {m['name']:<12} {oid:<14} {m['title']}{flag}")


if __name__ == "__main__":
    main()
