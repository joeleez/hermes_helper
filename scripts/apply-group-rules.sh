#!/usr/bin/env bash
# apply-group-rules.sh — 讓主持人只在指定群組「不需 @ 也收訊息」
#
# 用法： ./scripts/apply-group-rules.sh <chat_id> [container]
#
# 做的事：把 feishu.group_rules.<chat_id>.require_mention = false 寫進
#         容器的 /opt/data/config.yaml，並保留其他設定。
#
# 為什麼需要：主持人要能讀到「沒 @ 任何人」的訊息，才有機會決定該交給誰。
#             其他 agent 保持 require_mention=true，只在被 @ 時回應。
set -euo pipefail

CHAT_ID="${1:-}"
CONTAINER="${2:-hermes-pm}"

[ -n "$CHAT_ID" ] || { echo "用法：$0 <chat_id> [container]"; exit 1; }

docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "✗ 找不到容器 $CONTAINER"; exit 1; }

echo "目標容器：$CONTAINER"
echo "目標群組：$CHAT_ID"

docker exec -i -e CHAT_ID="$CHAT_ID" "$CONTAINER" /opt/hermes/.venv/bin/python - <<'PY'
import os, sys, shutil, datetime
import yaml

path = "/opt/data/config.yaml"
chat_id = os.environ["CHAT_ID"]

with open(path, encoding="utf-8") as fh:
    cfg = yaml.safe_load(fh) or {}

feishu = cfg.setdefault("feishu", {})
rules = feishu.setdefault("group_rules", {})
rule = rules.setdefault(chat_id, {})
before = dict(rule)
rule["require_mention"] = False

if before.get("require_mention") is False:
    print("  規則已存在，無需變更")
    sys.exit(0)

shutil.copy2(path, path + ".bak-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
header = (
    "# 由 hermes_helper 管理；改動後請重啟容器\n"
    "# feishu.group_rules：逐群規則。require_mention=false 表示不需 @ 也處理。\n"
)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(header)
    yaml.safe_dump(cfg, fh, allow_unicode=True, sort_keys=False)

print(f"  ✓ 已寫入 feishu.group_rules[{chat_id}].require_mention = false")
PY

echo
echo "重啟使設定生效："
echo "  docker compose restart pm"
