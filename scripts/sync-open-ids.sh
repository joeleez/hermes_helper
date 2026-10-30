#!/usr/bin/env bash
# sync-open-ids.sh — 把「主持人眼中」的 peer open_id 寫回 agents/<name>/agent.yml
#
# 為什麼不能用 /bot/v3/info：
#   Feishu 的 open_id 是 **每個 App 各自一套**。developer 用自己的憑證問會得到
#   ou_0d2be…（它眼中的自己），但 @ 是主持人發的，主持人只能用 ou_1a08…
#   （主持人眼中的 developer）。填錯的症狀：@ 到一個不存在的成員，對方永遠收不到。
#
# 怎麼拿主持人那一套：
#   用主持人的 token 讀群訊息歷史，收集 mentions[] 的 (name, open_id)。
#   只要有人 @ 過某個成員一次，就會被學會並寫進名冊。
#
# 用法： ./scripts/sync-open-ids.sh [chat_id]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CHAT_ID="${1:-}"

python3 - "$CHAT_ID" <<'PY'
import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.getcwd()
CHAT_ID = sys.argv[1] if len(sys.argv) > 1 else ""


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


def parse_agent(path):
    """極簡 YAML 讀取：只取我們需要的欄位，不引入 PyYAML。"""
    d = {"path": path, "name": os.path.basename(os.path.dirname(path))}
    section = None
    for line in open(path, encoding="utf-8"):
        raw = line.rstrip("\n")
        if not raw.strip() or raw.strip().startswith("#"):
            continue
        if not raw.startswith(" "):
            key, _, val = raw.partition(":")
            section = key.strip()
            d[section] = val.strip().strip('"')
            continue
        if section == "feishu":
            key, _, val = raw.strip().partition(":")
            d["feishu_" + key.strip()] = val.strip().strip('"')
    return d


agents = [parse_agent(p) for p in sorted(glob.glob("agents/*/agent.yml"))]
moderators = [a for a in agents if a.get("feishu_is_moderator") == "true"]
if not moderators:
    print("✗ 找不到主持人（agent.yml 內 is_moderator: true）")
    sys.exit(1)
mod = moderators[0]

merged = load_env(".env")
merged.update(load_env(".env." + mod["name"]))
app_id = merged.get("FEISHU_APP_ID", "")
secret = merged.get("FEISHU_APP_SECRET", "")
domain = merged.get("FEISHU_DOMAIN", "lark")
base = "https://open.larksuite.com" if domain == "lark" else "https://open.feishu.cn"

if not app_id or not secret:
    print(f"✗ 主持人 {mod['name']} 沒有憑證")
    sys.exit(1)


def post(path, payload):
    req = urllib.request.Request(base + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=20))


def get(path, tok, **q):
    if q:
        path += ("&" if "?" in path else "?") + "&".join("%s=%s" % (k, v) for k, v in q.items())
    req = urllib.request.Request(base + path, headers={"Authorization": "Bearer " + tok})
    return json.load(urllib.request.urlopen(req, timeout=25))


tok = post("/open-apis/auth/v3/tenant_access_token/internal",
           {"app_id": app_id, "app_secret": secret})["tenant_access_token"]

learned = {}
if CHAT_ID:
    page = None
    for _ in range(5):
        q = dict(container_id_type="chat", container_id=CHAT_ID,
                 sort_type="ByCreateTimeDesc", page_size=50)
        if page:
            q["page_token"] = page
        try:
            r = get("/open-apis/im/v1/messages", tok, **q)
        except urllib.error.HTTPError as exc:
            print(f"! 讀訊息歷史失敗 HTTP {exc.code}（需 im:message.group_msg）")
            break
        if r.get("code") != 0:
            print("! 讀訊息歷史失敗:", r.get("msg"))
            break
        data = r.get("data", {})
        for m in data.get("items", []):
            for mt in (m.get("mentions") or []):
                nm = (mt.get("name") or "").strip()
                oid = mt.get("id") or ""
                if nm and oid.startswith("ou_"):
                    learned.setdefault(nm, oid)
        page = data.get("page_token")
        if not data.get("has_more"):
            break

print(f"主持人：{mod['name']}（{mod.get('title')}）")
print(f"從群歷史學到 {len(learned)} 個 @ 目標")
for nm, oid in learned.items():
    print(f"  {nm} -> {oid}")

mod_self = get("/open-apis/bot/v3/info", tok)["bot"]["open_id"]

changed = warned = 0
for a in agents:
    name, title, path = a["name"], a.get("title", ""), a["path"]
    current = a.get("feishu_open_id", "")

    if a.get("feishu_is_moderator") == "true":
        new, note = mod_self, "主持人自身"
    elif title in learned:
        new, note = learned[title], "由群歷史驗證"
    else:
        new, note = current, "⚠ 群歷史未找到，沿用舊值（@ 可能失效）"
        warned += 1

    if new and new != current:
        text = open(path, encoding="utf-8").read()
        text = re.sub(r'(^\s*open_id:\s*)"[^"]*"', lambda m: m.group(1) + '"' + new + '"',
                      text, count=1, flags=re.M)
        open(path, "w", encoding="utf-8").write(text)
        changed += 1
        print(f"  ✓ {name:<12} {note}\n      {current[:14] or '(空)'}… -> {new[:14]}…")
    else:
        print(f"  = {name:<12} {note}（{current[:14] or '空'}…）")

print(f"\n完成：更新 {changed} 個，警告 {warned} 個")
if warned:
    print("提示：被警告的成員，需要有人在群裡 @ 它一次，或手動在 agent.yml 填 open_id。")

# 順帶清掉 sync-skills 留下的 .bak 目錄（會被 seed 當成技能複製進容器）
PY

echo
echo "→ 更新名冊"
if [ -n "$CHAT_ID" ]; then
  ./scripts/gen-roster.sh "$CHAT_ID"
else
  echo "  （未給 chat_id，略過）"
fi
