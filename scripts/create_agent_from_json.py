#!/usr/bin/env python3
"""create_agent_from_json.py — 讀 add_ai_agent.json，把 agent 完整建起來。

用法：
    python3 scripts/create_agent_from_json.py <表單路徑> [--dry-run] [--chat-id oc_xxx]

做的事（順序固定，任一步失敗就停）：
  1. 驗證表單（欄位齊、name slug 合法、role 合法、憑證可用 /bot/v3/info）
  2. 建 agents/<name>/agent.yml 與 SOUL.md
  3. 寫 .env.<name>（chmod 600）
  4. 在 docker-compose.yml 插入 service 區塊與 volume（只在 --dry-run 時跳過）
  5. 回報下一步（sync-open-ids / gen-roster / up -d）

安全：全程不印出 App Secret。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fail(msg: str) -> None:
    print(f"✗ {msg}")
    sys.exit(1)


def load_form(path: str) -> dict:
    if not os.path.exists(path):
        fail(f"找不到表單：{path}")
    try:
        with open(path, encoding="utf-8-sig") as fh:
            raw = json.load(fh)
    except json.JSONDecodeError as exc:
        fail(f"JSON 格式錯誤（第 {exc.lineno} 行）：{exc.msg}")
    form = {k.strip().lower().replace(" ", "_"): (v.strip() if isinstance(v, str) else v)
            for k, v in raw.items() if not k.startswith("_")}
    return form


def verify_app(app_id: str, secret: str, domain: str = "lark") -> str:
    base = "https://open.larksuite.com" if domain == "lark" else "https://open.feishu.cn"

    def post(path, payload):
        req = urllib.request.Request(base + path, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
        return json.load(urllib.request.urlopen(req, timeout=20))

    def get(path, token):
        req = urllib.request.Request(base + path, headers={"Authorization": "Bearer " + token})
        return json.load(urllib.request.urlopen(req, timeout=20))

    try:
        token = post("/open-apis/auth/v3/tenant_access_token/internal",
                     {"app_id": app_id, "app_secret": secret})["tenant_access_token"]
        bot = get("/open-apis/bot/v3/info", token).get("bot", {})
        return bot.get("app_name", "")
    except urllib.error.HTTPError as exc:
        fail(f"憑證驗證失敗（HTTP {exc.code}）：App ID 或 Secret 不正確，或應用未發布")
    except Exception as exc:  # noqa: BLE001
        fail(f"無法連上 Feishu 驗證憑證：{exc}")
    return ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("form")
    ap.add_argument("--dry-run", action="store_true", help="只驗證與產生檔案，不改 compose、不啟動")
    ap.add_argument("--chat-id", default=os.environ.get("FEISHU_GROUP_CHAT_ID", ""))
    args = ap.parse_args()

    form = load_form(args.form)
    app_id = form.get("app_id", "")
    secret = form.get("app_secret", "")
    name = form.get("name", "")
    detail = form.get("detail", "")
    raw_role = (form.get("role") or "工作人員").strip()

    # 接受中文與英文寫法，但只允許兩種可生成的角色
    ROLE_MAP = {
        "群組主持人": "moderator", "主持人": "moderator", "moderator": "moderator",
        "工作人員": "specialist", "專員": "specialist", "員工": "specialist",
        "specialist": "specialist", "staff": "specialist", "worker": "specialist",
    }
    FORBIDDEN = {"後台管理員", "管理員", "operator", "admin"}
    role_key = raw_role.lower()
    if role_key in FORBIDDEN:
        fail("後台管理員是操作者本人（宿主層），不能生成第二個。\n"
             "  它擁有 Docker 與 repo 寫入權限，只應該有一個。\n"
             "  如果你要的是『幫你協調的人』，填「群組主持人」。")
    if role_key not in ROLE_MAP:
        fail(f"role 只接受「群組主持人」或「工作人員」（也接受 moderator / specialist），收到：{raw_role!r}")
    role = ROLE_MAP[role_key]

    missing = [k for k, v in (("App_ID", app_id), ("App_Secret", secret),
                              ("name", name), ("detail", detail)) if not v]
    if missing:
        fail(f"表單缺少欄位：{', '.join(missing)}")
    if not re.fullmatch(r"[a-z][a-z0-9_-]*", name):
        fail(f"name 不合法：{name!r} —— 只能小寫字母開頭，含 a-z 0-9 - _")
    if role not in ("moderator", "specialist"):
        fail(f"role 不合法：{role!r} —— 只能是 moderator 或 specialist")
    if "在這裡貼" in app_id or "在這裡貼" in secret:
        fail("表單仍是預設範例值，請填入真實的 App ID / Secret")

    title = form.get("title") or detail.split("，")[0][:20]

    if args.dry_run:
        print("（dry-run：跳過憑證驗證）")
        app_name = "(dry-run)"
    else:
        app_name = verify_app(app_id, secret)
        print(f"✓ 憑證可用，Feishu 應用名稱：{app_name}")

    agent_dir = os.path.join(ROOT, "agents", name)
    if os.path.exists(agent_dir):
        fail(f"agents/{name} 已存在，請換 name 或先移除")
    os.makedirs(agent_dir)

    is_mod = role == "moderator"
    with open(os.path.join(agent_dir, "agent.yml"), "w", encoding="utf-8") as fh:
        fh.write(f"""name: {name}
title: "{title}"
description: "{detail}"
capabilities:
  - （由表單 detail 展開，可之後補充）
cannot:
  - （補上它不該做什麼）
feishu:
  open_id: ""
  is_moderator: {str(is_mod).lower()}
  require_mention: {str(not is_mod).lower()}
""")

    with open(os.path.join(agent_dir, "SOUL.md"), "w", encoding="utf-8") as fh:
        fh.write(f"""# SOUL — {title}

## 你是誰

**開場先讀兩份檔案**（不要憑記憶，人類可能改過）：

```
/opt/data/identity.yaml      你是誰：名字、open_id、role、同伴清單
/opt/data/roster.yaml        群裡每個人的職責與 open_id
```

再讀 `skills/group-protocol`（群裡共用的溝通規矩）。

你的職責：{detail}

## 工作方式

1. 只做被交辦的事；不確定就問一個具體問題
2. 完成後回報：做了什麼、怎麼驗證、風險
3. 不要聲稱完成而沒有證據

## 語言

繁體中文（香港用語可），技術名詞保留英文。
""")

    env_path = os.path.join(ROOT, f".env.{name}")
    with open(env_path, "w", encoding="utf-8") as fh:
        fh.write(f"AGENT_NAME={name}\nFEISHU_APP_ID={app_id}\nFEISHU_APP_SECRET={secret}\n")
    os.chmod(env_path, 0o600)

    print(f"✓ agents/{name}/agent.yml + SOUL.md")
    print(f"✓ .env.{name}（chmod 600，{len(secret)} 字 secret）")

    compose = os.path.join(ROOT, "docker-compose.yml")
    if args.dry_run:
        print("（dry-run：未修改 docker-compose.yml）")
    else:
        text = open(compose, encoding="utf-8").read()
        if f"container_name: hermes-{name}" in text:
            fail("docker-compose.yml 已有同名 service")
        block = f"""  {name}:
    build:
      context: .
    image: hermes-helper-pm:local
    container_name: hermes-{name}
    restart: unless-stopped
    command: ["gateway"]
    env_file:
      - .env
      - .env.{name}
    environment:
      AGENT_NAME: {name}
      HERMES_HOME: /opt/data
    volumes:
      - {name}-data:/opt/data
      - ./scripts/seed-agent.sh:/etc/cont-init.d/99-seed-agent:ro
      - ./agents:/opt/bootstrap/agents:ro
      - ./skills:/opt/bootstrap/skills:ro
    stop_grace_period: 30s
    healthcheck:
      test: ["CMD-SHELL", "test -f /opt/data/config.yaml || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s

"""
        idx = text.rfind("\nvolumes:\n")
        if idx == -1:
            fail("docker-compose.yml 找不到 volumes: 段落，請手動加入 service")
        text = text[:idx + 1] + block + text[idx + 1:]
        text = text.rstrip("\n") + f"\n  {name}-data:\n    name: hermes-{name}-data\n"
        open(compose, "w", encoding="utf-8").write(text)

        check = subprocess.run(["docker", "compose", "config", "--quiet"], cwd=ROOT,
                               capture_output=True, text=True)
        if check.returncode != 0:
            shutil.copy2(compose + "", compose + ".broken")
            fail("compose 驗證失敗，已保留 docker-compose.yml.broken 供檢查")
        print("✓ docker-compose.yml 已加入 service並通過 compose config 驗證")

    chat = args.chat_id
    print("\n下一步（依序執行）：")
    print(f"  ./scripts/sync-open-ids.sh")
    print(f"  ./scripts/gen-roster.sh {chat or '<chat_id>'}")
    print(f"  docker compose up -d {name}")
    print(f"  docker compose up -d --force-recreate pm")
    print(f"  ./scripts/doctor.sh {chat or '<chat_id>'}")


if __name__ == "__main__":
    main()
