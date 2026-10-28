#!/bin/bash
# seed-agent.sh — s6 cont-init 鉤子（root 執行，在服務啟動前）
#
# 兩個踩過的坑，這裡都處理了：
#   1. s6 會「清空環境變數」才執行 cont-init，所以必須從
#      /run/s6/container_environment/ 自己 rehydrate（with-contenv 就是做這件事）
#   2. 官方 01-hermes-setup 會先塞一份預設 SOUL.md 與 config 範本，
#      所以不能靠「檔案不存在」判斷首次啟動 → 用 marker 檔
#
# 掛載位置：/etc/cont-init.d/99-seed-agent（故意排在官方 01- 之後）
set -euo pipefail

# ── 0. rehydrate 容器環境 ──────────────────────────
if [ -d /run/s6/container_environment ]; then
  for f in /run/s6/container_environment/*; do
    [ -f "$f" ] || continue
    export "$(basename "$f")=$(cat "$f")"
  done
fi

AGENT_NAME="${AGENT_NAME:-pm}"
H="${HERMES_HOME:-/opt/data}"
B="${BOOTSTRAP_DIR:-/opt/bootstrap}"
MARKER="$H/.seeded-by-hermes-helper"

log() { echo "[seed:$AGENT_NAME] $*"; }

mkdir -p "$H/skills" "$H/memories"

# ── 1. 首次 seed（用 marker，不用檔案存在與否）──────
if [ ! -f "$MARKER" ]; then
  log "首次啟動：套用框架（會覆寫官方預設的 SOUL.md / config.yaml）"

  if [ -f "$B/agent/SOUL.md" ]; then
    cp "$B/agent/SOUL.md" "$H/SOUL.md"
    log "SOUL.md ← agents/$AGENT_NAME/SOUL.md"
  else
    log "警告：找不到 $B/agent/SOUL.md"
  fi

  if [ -d "$B/skills" ]; then
    for d in "$B"/skills/*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      rm -rf "$H/skills/$name"
      cp -r "$d" "$H/skills/$name"
    done
    log "skills：$(ls "$H/skills" 2>/dev/null | tr '\n' ' ')"
  fi

  # 記憶骨架（不覆蓋既有）
  for f in MEMORY USER; do
    if [ ! -f "$H/memories/$f.md" ]; then
      printf '# %s\n\n（首次啟動建立，尚無內容。）\n' "$f" > "$H/memories/$f.md"
    fi
  done

  cat > "$H/config.yaml" <<YAML
# 由 hermes_helper 的 seed-agent.sh 產生（首次啟動）。
# 之後可自由編輯；要重新 seed 請刪 $MARKER 後重啟容器。
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
  log "config.yaml 已寫入（model=${HERMES_MODEL:-未設定}）"

  date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER"
else
  log "已 seed 過（$(cat "$MARKER" 2>/dev/null)），保留既有記憶與設定"
fi

# ── 2. secrets → $H/.env（每次啟動刷新）────────────
TMP="$H/.env.tmp"
: > "$TMP"
n=0
for v in DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY \
         GOOGLE_API_KEY XAI_API_KEY \
         FEISHU_APP_ID FEISHU_APP_SECRET FEISHU_CONNECTION_MODE \
         FEISHU_GROUP_POLICY FEISHU_REQUIRE_MENTION FEISHU_ALLOW_BOTS; do
  val="${!v:-}"
  if [ -n "$val" ]; then
    printf '%s=%s\n' "$v" "$val" >> "$TMP"
    n=$((n+1))
  fi
done
mv "$TMP" "$H/.env"
chmod 600 "$H/.env" 2>/dev/null || true
log ".env 已寫入（$n 個變數）"

# ── 3. 權限對齊 ────────────────────────────────────
if id hermes >/dev/null 2>&1; then
  chown -R hermes:hermes "$H" 2>/dev/null || true
fi

log "完成"
