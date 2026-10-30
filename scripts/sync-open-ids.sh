#!/usr/bin/env bash
# sync-open-ids.sh — 把每個 agent 的 bot open_id 寫回 agents/<name>/agent.yml
#
# 為什麼需要：Feishu 的群成員 API 只回人類，機器人不在清單裡。
# 所以名冊不能靠「掃群成員」補 open_id，只能每個 agent 用自己的憑證問
# /open-apis/bot/v3/info。
#
# 用法： ./scripts/sync-open-ids.sh
#        憑證來源：.env.<name>（沒有就用 .env）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import glob
import json
import os
import re
import urllib.error
import urllib.request

ROOT = os.getcwd()


def load_env(path):
    env = {}
    if not os.path.exists(path):
        return env
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k, v = s.split("=", 1)
            env[k.strip()] = v.strip()
    return env


def bot_open_id(env):
    app_id = env.get("FEISHU_APP_ID", "")
    secret = env.get("FEISHU_APP_SECRET", "")
    if not app_id or not secret:
        return None, "缺少憑證"
    base = "https://open.larksuite.com" if env.get("FEISHU_DOMAIN") == "lark" else "https://open.feishu.cn"

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
        return bot.get("open_id"), bot.get("app_name", "")
    except urllib.error.HTTPError as exc:
        return None, f"HTTP {exc.code}"
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)


changed = 0
for agent_yml in sorted(glob.glob(os.path.join(ROOT, "agents", "*", "agent.yml"))):
    name = os.path.basename(os.path.dirname(agent_yml))
    env_path = os.path.join(ROOT, f".env.{name}")
    if not os.path.exists(env_path):
        env_path = os.path.join(ROOT, ".env")
    env = load_env(env_path)

    oid, info = bot_open_id(env)
    if not oid:
        print(f"  ✗ {name:<12} 取不到 open_id（{info}）")
        continue

    text = open(agent_yml, encoding="utf-8").read()
    new_text, n = re.subn(r'^\s*open_id:\s*.*$', f'  open_id: "{oid}"', text, count=1, flags=re.M)
    if n == 0:
        print(f"  ! {name:<12} agent.yml 沒有 open_id 欄位，跳過")
        continue
    if new_text != text:
        open(agent_yml, "w", encoding="utf-8").write(new_text)
        changed += 1
        print(f"  ✓ {name:<12} open_id 已更新 → {oid[:12]}…  （{info}）")
    else:
        print(f"  = {name:<12} 已是 {oid[:12]}…（{info}）")

print(f"\n完成，更新 {changed} 個 agent.yml")
PY
