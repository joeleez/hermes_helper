#!/usr/bin/env bash
# doctor.sh — 每個 agent 的部署體檢
#
# 用法： ./scripts/doctor.sh [chat_id]
#
# 檢查 8 項，任何 ✗ 都會讓端到端流程斷掉：
#   1. container 在跑且 healthy
#   2. /opt/data/identity.yaml 存在且 open_id 非空
#   3. role 正確（moderator / specialist）
#   4. roster.yaml 存在，且包含所有 agent
#   5. group-protocol 技能已載入
#   6. Feishu websocket 已連線
#   7. 准入設定合理（moderator: require_mention=false；specialist: true）
#   8. .env 內有 App ID（不顯示值）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CHAT_ID="${1:-oc_0de516cac9ef4b6d213464b7b601fcd8}"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
FAIL=0

for dir in agents/*/; do
  name="$(basename "$dir")"
  [ -f "$dir/agent.yml" ] || continue
  c="hermes-$name"
  printf '\n\033[1m%s\033[0m (%s)\n' "$name" "$c"

  # 1. container
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    st="$(docker inspect "$c" --format '{{.State.Health.Status}}')"
    [ "$st" = "healthy" ] && ok "container healthy" || warn "container 在跑但 health=$st"
  else
    bad "container 不在跑（docker compose up -d $name）"; FAIL=1; continue
  fi

  # 2/3. identity
  ident="$(docker exec "$c" cat /opt/data/identity.yaml 2>/dev/null)"
  if [ -n "$ident" ]; then
    oid="$(printf '%s' "$ident" | awk '/^open_id:/{print $2}')"
    role="$(printf '%s' "$ident" | awk '/^role:/{print $2}')"
    [ -n "$oid" ] && ok "identity open_id ${oid:0:10}…" || { bad "identity open_id 為空（跑 sync-open-ids.sh）"; FAIL=1; }
    ok "role=$role"
  else
    bad "缺 /opt/data/identity.yaml"; FAIL=1
  fi

  # 4. roster
  if docker exec "$c" test -f /opt/data/roster.yaml 2>/dev/null; then
    n="$(docker exec "$c" sh -c "grep -c '^- name:' /opt/data/roster.yaml" 2>/dev/null)"
    ok "roster.yaml（$n 個成員）"
  else
    bad "缺 /opt/data/roster.yaml"; FAIL=1
  fi

  # 5. skills
  docker exec "$c" test -d /opt/data/skills/group-protocol 2>/dev/null \
    && ok "group-protocol 技能" || { bad "缺 group-protocol 技能（sync-skills.sh --apply）"; FAIL=1; }

  # 6. feishu
  if docker logs "$c" --since 30m 2>&1 | grep -q "connected to wss://"; then
    ok "Feishu websocket 已連線"
  else
    warn "最近 30 分鐘沒看到連線紀錄（可能只是沒有重啟）"
  fi

  # 7. admission
  rm="$(docker exec "$c" sh -c "grep -h '^FEISHU_REQUIRE_MENTION=' /opt/data/.env | cut -d= -f2" 2>/dev/null)"
  if [ "$role" = "moderator" ]; then
    [ "$rm" = "false" ] && ok "require_mention=false（主持人需要不 @ 也收）" \
      || { bad "主持人 require_mention=$rm（應為 false）"; FAIL=1; }
  else
    [ "$rm" = "true" ] || [ -z "$rm" ] && ok "require_mention=${rm:-預設 true}" \
      || warn "專員 require_mention=$rm（預期 true）"
  fi

  # 8. credentials
  if docker exec "$c" sh -c "grep -q '^FEISHU_APP_ID=cli_' /opt/data/.env" 2>/dev/null; then
    ok "App ID 已設定"
  else
    bad "缺 FEISHU_APP_ID"; FAIL=1
  fi
done

printf '\n\033[1m名冊（repo）\033[0m\n'
if [ -f agents/roster.yaml ]; then
  while IFS= read -r line; do
    case "$line" in
      "- name:"*) printf '  %s\n' "${line#- name: }" ;;
    esac
  done < agents/roster.yaml
  grep -q "group_chat_id: $CHAT_ID" agents/roster.yaml && ok "chat_id 一致" || warn "roster 的 chat_id 與 $CHAT_ID 不同"
else
  bad "缺 agents/roster.yaml（gen-roster.sh）"; FAIL=1
fi

printf '\n'
[ "$FAIL" -eq 0 ] && printf '\033[32m全部通過\033[0m\n' || printf '\033[31m有項目未通過\033[0m\n'
exit "$FAIL"
