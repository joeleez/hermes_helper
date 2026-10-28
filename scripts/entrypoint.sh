#!/usr/bin/env bash
# entrypoint.sh — 容器啟動入口
#
# 行為：
#   1. 第一次啟動（/opt/data/config.yaml 不存在）→ 從框架 seed SOUL / skills / config / 記憶骨架
#   2. 之後啟動 → 完全使用 /opt/data，不覆蓋任何東西
#   3. 把容器環境的 secrets 寫進 /opt/data/.env（Hermes 從那裡讀）
#   4. exec hermes <command>（預設 gateway）
set -euo pipefail

AGENT_NAME="${AGENT_NAME:-pm}"
H="${HERMES_HOME:-/opt/data}"
B="${BOOTSTRAP_DIR:-/opt/bootstrap}"
CMD="${1:-gateway}"

log() { echo "[entrypoint][$AGENT_NAME] $*"; }

mkdir -p "$H" "$H/skills" "$H/memories"

# ── 1. 首次初始化 ──────────────────────────────────
if [ ! -f "$H/config.yaml" ]; then
  log "首次啟動：初始化 $H"

  if [ -f "$B/agent/SOUL.md" ] && [ ! -f "$H/SOUL.md" ]; then
    cp "$B/agent/SOUL.md" "$H/SOUL.md"
    log "已安裝 SOUL.md"
  fi

  if [ -d "$B/skills" ]; then
    cp -r "$B/skills/." "$H/skills/"
    log "已安裝 skills：$(ls "$H/skills" | tr '\n' ' ')"
  fi

  for f in MEMORY USER; do
    if [ ! -f "$H/memories/$f.md" ]; then
      {
        echo "# $f"
        echo
        echo "（首次啟動建立，尚無內容。之後累積的記憶會寫在這裡。）"
      } > "$H/memories/$f.md"
    fi
  done

  # 最小可用 config（金鑰不放這裡，放 .env）
  cat > "$H/config.yaml" <<YAML
# 由 entrypoint 首次啟動時產生；之後可直接編輯（改完重啟容器）
model:
  default: "${HERMES_MODEL:-}"

memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200

gateway:
  multiplex_profiles: false
  bot_loop_guard:
    enabled: true
    max_events: 20
    window_seconds: 300
    cooldown_seconds: 600

security:
  redact_secrets: true
YAML
  log "已產生 config.yaml（model=${HERMES_MODEL:-未設定}）"
else
  log "使用既有資料（$H 已存在）"
fi

# ── 2. 把 secrets 從容器環境寫進 Hermes 的 .env ──
TMP="$H/.env.tmp"
: > "$TMP"
for v in DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY \
         GOOGLE_API_KEY XAI_API_KEY \
         FEISHU_APP_ID FEISHU_APP_SECRET FEISHU_CONNECTION_MODE \
         FEISHU_GROUP_POLICY FEISHU_REQUIRE_MENTION FEISHU_ALLOW_BOTS; do
  val="${!v:-}"
  if [ -n "$val" ]; then
    printf '%s=%s\n' "$v" "$val" >> "$TMP"
  fi
done
mv "$TMP" "$H/.env"
chmod 600 "$H/.env" 2>/dev/null || true
log "已寫入 .env（$(grep -c . "$H/.env" || echo 0) 個變數）"

# ── 3. 交給 Hermes ────────────────────────────────
if ! command -v hermes >/dev/null 2>&1; then
  log "錯誤：映像裡找不到 hermes 指令"
  log "請確認 image 是 nousresearch/hermes-agent，或改用官方 entrypoint"
  exit 1
fi

log "啟動：hermes $CMD"
exec hermes "$CMD"
