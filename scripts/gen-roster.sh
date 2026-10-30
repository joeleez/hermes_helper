#!/usr/bin/env bash
# gen-roster.sh — 生成 agent 名冊（給群組主持人讀）
#
# 用法：
#   ./scripts/gen-roster.sh                    # 用 .env 裡的憑證，群別取自 FEISHU_GROUP_CHAT_ID
#   ./scripts/gen-roster.sh oc_xxxxxxxx        # 指定群
#
# 只讀 agents/*/agent.yml 與 Feishu 成員清單，不改任何 agent 狀態。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 取得憑證（.env → 環境變數）
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# 用 Hermes 的 venv 跑（裡面有 PyYAML）；沒有就退回系統 python3
PY="python3"
if [ -x /opt/hermes/.venv/bin/python ]; then PY=/opt/hermes/.venv/bin/python; fi

exec "$PY" scripts/gen_roster.py "${1:-}"
