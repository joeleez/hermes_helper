#!/usr/bin/env bash
# sync-skills.sh — 把 repo 的 skills/ 同步進正在運行的 agent
#
# 用法： ./scripts/sync-skills.sh          # 預覽
#        ./scripts/sync-skills.sh --apply  # 實際同步（先備份被覆蓋的）
#
# 為什麼要手動：entrypoint 只在首次啟動時 seed。
# 之後 repo 改了技能，必須明確同步，避免覆蓋 agent 自己演化出來的版本。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="${CONTAINER:-hermes-pm}"
APPLY="${1:-}"
STAMP="$(date +%Y%m%d-%H%M%S)"

docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || {
  echo "✗ 容器 $CONTAINER 沒在跑。先 docker compose up -d"; exit 1; }

echo "repo：$REPO_DIR/skills"
echo "容器：$CONTAINER:/opt/data/skills"
echo

for src in "$REPO_DIR"/skills/*/; do
  name="$(basename "$src")"
  if docker exec "$CONTAINER" test -d "/opt/data/skills/$name"; then
    echo "  ~ $name（已存在，同步時會備份）"
  else
    echo "  + $name（新增）"
  fi
done

if [ "$APPLY" != "--apply" ]; then
  echo; echo "這是預覽。要真的同步請加 --apply"; exit 0
fi

echo
for src in "$REPO_DIR"/skills/*/; do
  name="$(basename "$src")"
  docker exec "$CONTAINER" sh -c "mkdir -p /opt/data/.skill-backups && [ -d /opt/data/skills/$name ] && mv /opt/data/skills/$name /opt/data/.skill-backups/$name.bak-$STAMP" || true
  docker cp "$src" "$CONTAINER:/opt/data/skills/$name"
  echo "  已同步 $name"
done
echo "完成。備份在 /opt/data/.skill-backups/"
