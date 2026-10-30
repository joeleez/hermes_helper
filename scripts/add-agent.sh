#!/usr/bin/env bash
# add-agent.sh — 操作者用的腳本：為新 agent 產生角色檔，並印出需要貼進 compose 的區塊
#
# 用法：
#   ./scripts/add-agent.sh <name> "<title>" "<一句話職責>" [--moderator]
#
# 例：
#   ./scripts/add-agent.sh reviewer "審查員" "審查方案與程式碼，專找漏洞與邊界條件"
#
# 它只做三件事（不碰 compose、不碰 .env、不啟容器）：
#   1. 建 agents/<name>/agent.yml
#   2. 建 agents/<name>/SOUL.md 骨架
#   3. 印出 compose service 區塊與後續步驟
#
# 為什麼不自動改 compose：compose 是部署的單一真相，改壞會讓所有 agent 一起掛。
# 人看一眼、貼上去，比自動重寫 YAML 安全。
set -euo pipefail

NAME="${1:-}"
TITLE="${2:-}"
DESC="${3:-}"
ROLE_FLAG="${4:-}"

[ -n "$NAME" ] && [ -n "$TITLE" ] && [ -n "$DESC" ] || {
  echo "用法：$0 <name> \"<title>\" \"<一句話職責>\" [--moderator]"
  exit 1
}

[[ "$NAME" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "✗ name 只能用 a-z 0-9 - _，且以字母開頭"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/agents/$NAME"

[ -e "$DIR" ] && { echo "✗ agents/$NAME 已存在"; exit 1; }

IS_MODERATOR=false
REQUIRE_MENTION=true
if [ "$ROLE_FLAG" = "--moderator" ]; then
  IS_MODERATOR=true
  REQUIRE_MENTION=false
fi

mkdir -p "$DIR"

cat > "$DIR/agent.yml" <<YAML
name: $NAME
title: "$TITLE"
description: "$DESC"
capabilities:
  - （補上這個 agent 具體會做什麼）
cannot:
  - （補上它不該做什麼）
feishu:
  # 由 scripts/sync-open-ids.sh 自動填入
  open_id: ""
  is_moderator: $IS_MODERATOR
  require_mention: $REQUIRE_MENTION
YAML

cat > "$DIR/SOUL.md" <<MD
# SOUL — $TITLE

## 你是誰

**開場先讀兩份檔案**（不要憑記憶，人類可能改過）：

\`\`\`
/opt/data/identity.yaml      你是誰：名字、open_id、role、同伴清單
/opt/data/roster.yaml        群裡每個人的職責與 open_id
\`\`\`

再讀 \`skills/group-protocol\`（群裡共用的溝通規矩）。

你的職責：$DESC

## 工作方式

1. 只做被交辦的事；不確定就問一個具體問題
2. 完成後回報：做了什麼、怎麼驗證、風險
3. 不要聲稱完成而沒有證據

## 語言

繁體中文（香港用語可），技術名詞保留英文。
MD

echo "✓ 已建立 agents/$NAME/"
echo "  - agent.yml（role=$([ "$IS_MODERATOR" = true ] && echo moderator || echo specialist)）"
echo "  - SOUL.md（骨架，請補上工作細節）"
echo
echo "── 下一步 ──────────────────────────────────────"
echo "1) 寫入 Feishu 憑證（不要貼在聊天，用 read -s）："
echo
echo "   read -rsp \"App ID: \" ID; echo"
echo "   read -rsp \"App Secret: \" SEC; echo"
echo "   printf 'AGENT_NAME=$NAME\\nFEISHU_APP_ID=%s\\nFEISHU_APP_SECRET=%s\\n' \"\$ID\" \"\$SEC\" > .env.$NAME"
echo "   unset ID SEC; chmod 600 .env.$NAME"
echo
echo "2) 把下面區塊貼進 docker-compose.yml（services: 之下），並在 volumes: 加一行："
echo
cat <<YAML
  $NAME:
    build:
      context: .
    image: hermes-helper-pm:local
    container_name: hermes-$NAME
    restart: unless-stopped
    command: ["gateway"]
    env_file:
      - .env
      - .env.$NAME
    environment:
      AGENT_NAME: $NAME
      HERMES_HOME: /opt/data
    volumes:
      - $NAME-data:/opt/data
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

# volumes:
#   $NAME-data:
#     name: hermes-$NAME-data
YAML
echo
echo "3) 同步與啟動："
echo "   ./scripts/sync-open-ids.sh"
echo "   ./scripts/gen-roster.sh <chat_id>"
echo "   docker compose up -d $NAME"
echo "   docker compose up -d --force-recreate pm    # 主持人重載名冊"
echo
echo "4) 把 bot 拉進群後，再跑一次 sync-open-ids.sh 與 gen-roster.sh"
echo "5) 驗證：docker exec hermes-$NAME cat /opt/data/identity.yaml"
